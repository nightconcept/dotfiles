---
name: rinoa-migration
description: Move a self-hosted Docker service from another host to the Rinoa NixOS server. Use when asked to migrate, relocate, or consolidate a service onto Rinoa; update its NixOS container module, Traefik route, health checks, persistent state, and cutover procedure safely.
---

# Rinoa Service Migration

Use this workflow to move one service at a time to Rinoa (`192.168.1.110`). Rinoa runs Docker services through NixOS modules and is the Traefik host.

## Discover the Current Service

1. Read `AGENTS.md`, `hosts/CLAUDE.md`, `modules/CLAUDE.md`, and `modules/nixos/services/docker/CLAUDE.md`. Read the target container's local `CLAUDE.md` when present.
2. Locate the active deployment, data directory, bind mounts, port, monitoring checks, and reverse-proxy route with `rg`.
3. Identify every persistent path. Treat SQLite databases, uploaded files, and conversion queues as state that must not have concurrent writers.
4. Confirm Rinoa has the dependencies the service needs. For Titan-backed services, require `/mnt/titan` and make the service depend on `mnt-titan.mount`.

## Implement the Rinoa Module

Follow the local container convention:

1. Add `modules/nixos/services/docker/containers/<service>/default.nix` and `docker-compose.yml`.
2. Import it in `modules/nixos/services/docker/default.nix`.
3. Expose an enable option under `modules.nixos.docker.containers.<service>` and enable it in `hosts/nixos/rinoa/default.nix`.
4. Use `/var/lib/docker-containers/<service>` for runtime state unless the existing module pattern requires another persistent path.
5. Add a Docker health check. Add the container name to Rinoa's `healthCheck.expectedContainers` and its unit to `healthCheck.afterUnits`.
6. Put services behind the external `proxy` Docker network and configure Traefik labels. Prefer labels over a static Traefik backend when the service runs on Rinoa.
7. Pin source-built services as a flake input. Do not require an unmanaged checkout on Rinoa.

## Validate Before Cutover

Run the smallest relevant checks first, then the Rinoa system evaluation:

```bash
docker compose -f modules/nixos/services/docker/containers/<service>/docker-compose.yml config
NIXPKGS_ALLOW_UNFREE=1 nix eval --impure .#nixosConfigurations.rinoa.config.systemd.services.docker-container-<service>.serviceConfig.ExecStart --raw
NIXPKGS_ALLOW_UNFREE=1 nix build --impure .#nixosConfigurations.rinoa.config.system.build.toplevel --dry-run
git diff --check
```

Do not switch Rinoa or stop the source service until these checks pass and the user authorizes the live cutover.

## Cut Over Safely

1. Ensure the Rinoa configuration and required source closure are available.
2. Stop the source service before copying mutable state.
3. Copy persistent state to Rinoa with ownership and timestamps preserved. Do not copy Titan media paths that are already shared.
4. Switch Rinoa, then confirm the unit is active, the container is healthy, the Rinoa readiness endpoint passes, and the routed HTTPS URL responds.
5. Remove static Traefik routes that still point to the old host. Update or remove old-host direct monitors; retain the end-user routed monitor.
6. Only remove the old deployment wiring after the new service has passed all checks.

## Verify and Roll Back

Verify with:

```bash
systemctl status docker-container-<service>
docker inspect --format '{{.State.Health.Status}}' <service>
curl --fail http://192.168.1.110:3002/health
curl --fail https://<service>.local.solivan.dev/
```

If startup or routing fails, stop the Rinoa container, restore the old Traefik backend, and restart the source service using its original state. Do not run both instances against the same writable state.

## Scope Controls

- Do not alter unrelated host services or secrets.
- Do not create or update documentation unless asked.
- Preserve unrelated working-tree changes.
- Ask before commands that switch hosts, stop services, transfer production state, or otherwise change live systems.
