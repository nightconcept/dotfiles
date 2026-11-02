# Docker Configuration

Docker services are managed as Nix modules in `/modules/nixos/services/docker/containers/`. Each container has its own module that defines:
- Docker compose configuration
- Environment variables
- Volume mounts
- Network configuration
- Traefik labels for reverse proxy

Available container modules include:
- **Media**: jellyfin, plex
- ***arr Stack**: sonarr, sonarr-anime, radarr, recyclarr, prowlarr, readarr, flaresolverr
- **Books**: audiobookshelf, calibre, calibre-web, readarr-books
- **Home Automation**: homepage, uptime-kuma, gotify
- **Infrastructure**: traefik, portainer, watchtower (Nicholas Fedor fork), cloudflare-tunnel, headscale
- **Media requests**: seerr (the supported successor to Overseerr and Jellyseerr)
- **Authentication**: vaultwarden
- **Development**: forgejo, forgejo-runner, paseo
- **Gaming**: minecraft, enshrouded, palworld
- **Utilities**: freshrss, nextcloud, open-webui, searxng, wg-easy, ddclient, knot

Docker networks:
- `proxy` - Shared network for services behind Traefik reverse proxy

Rinoa runs the maintained `ghcr.io/nicholas-fedor/watchtower` fork daily at
04:00. Updates are opt-in: only running containers with the
`com.centurylinklabs.watchtower.enable=true` label are updated, and superseded
images are removed afterward. Watchtower follows the configured image tag; it
does not promote a pinned tag such as `3.5.2` to a newer release line.

## Gotify Notifications (Vincent)

Gotify on Vincent pushes alerts for work that needs a person. It listens on
`http://192.168.1.185:8070`, and Rinoa's Traefik routes
`https://gotify.local.solivan.dev` to it (LAN and VPN clients only).

- **Uptime Kuma** sends monitor down/up and certificate expiry alerts through
  a default `Gotify` notification attached to every monitor.
- **Watchtower** on Vincent sends a report after it updates containers or
  fails to update them.
- **Disk space**: `gotify-disk-alert.timer` checks `/` every hour. It sends
  an alert when usage is at or above 85%, repeats it every 24 hours while the
  disk stays full, and sends one message when usage goes below 85%.

On the first start, the module generates the admin password in
`/var/lib/docker-containers/gotify/admin-password`. `gotify-provision.service`
creates the `uptime-kuma`, `watchtower` and `hermes-alerts` applications. Gotify 3 shows an
application token only once, so the service stores each token in
`/var/lib/docker-containers/gotify/tokens/`. If a token file is missing, the
service rotates that application's token. The `host-alerts` application is
added when `diskAlert.enable` is set.

To receive alerts, log in to the web UI as `admin`, then add a client in the
Gotify Android app (or another Gotify client) with the server URL.

## Security stack and reverse-proxy protection

The shared security package has central and sensor roles.
Vincent runs central EveBox/Wazuh services and a local sensor. Rinoa runs a local sensor that reports to Vincent.
Gotify remains on Vincent. CrowdSec remains on reverse-proxy hosts such as Rinoa.
See [the distributed security architecture](security.md) for package boundaries, capture interfaces, placement findings, and implementation status.

The module is `modules/nixos/services/docker/containers/security-stack/default.nix`.
Both host declarations enable their selected role on the next rebuild.
Vincent and Rinoa are active with healthy central and sensor containers.
The encrypted bridge token remains in `modules/nixos/security/sops/suricata.yaml`.
The package passed isolated central and remote-sensor tests on Terra.
See [enablement and test evidence](security.md#enable-vincent-first).

Run the package checks with the repository's Python environment:

```sh
uv run python -m unittest discover -s modules/nixos/services/docker/containers/security-stack -p 'test_*.py'
```

### CrowdSec on Rinoa

The configured CrowdSec service reads Traefik's existing `traefik_traefik-logs` volume.
Its bouncer key is registered through `BOUNCER_KEY_traefik` and shared with the existing Traefik bouncer.
Only routers with `crowdsec-bouncer@docker` enforce CrowdSec decisions. There is no host firewall bouncer or outbound filtering.
The acquisition whitelist covers the LAN and Headscale IPv4/IPv6 ranges to preserve trusted client access.
Traefik's LAN access rules also permit the Headscale IPv4/IPv6 ranges.
This whitelist prevents detection from creating bans. It does not remove existing manual decisions.
Barrett's NordVPN traffic and direct LAN services do not pass through this middleware.

Recent Traefik logs included Docker gateway addresses instead of public client addresses.
Cloudflare Tunnel client attribution needs validation before relying on CrowdSec for those requests.
Do not enable unrestricted trust of forwarded headers to resolve this.

Deploy the full Rinoa host from its repository checkout:

```sh
sudo nixos-rebuild switch --flake 'path:.#rinoa'
```

Check CrowdSec acquisition and bouncer registration:

```sh
docker exec crowdsec cscli metrics show acquisition
docker exec crowdsec cscli bouncers list
```

Terra checks parsed four synthetic Traefik records.
The test bouncer blocked a banned address and allowed LAN and Headscale clients.
These checks do not validate every VPN application.

## Forgejo Runner Image Cache

The `forgejo-dind` container keeps its image cache in the named volume
`forgejo-runners_forgejo-dind-data`. Before this volume existed, each
recreation of the container left behind an anonymous `/var/lib/docker` volume
of 2-10 GB. `forgejo-dind-prune.timer` runs weekly and removes images that
have not been used for 7 days.

## Finance services on Rinoa

The `finance` module manages Actual Budget and Paisa on Rinoa.
Both containers use the `proxy` network. Neither container publishes a host port.
Traefik permits LAN and Headscale clients through `secured@file`.

- `https://budget.local.solivan.dev` routes to Actual Budget, container port 5006.
- `https://ledger.local.solivan.dev` routes to Paisa, container port 7500.

The image digests preserve the versions from Terra during migration.
Update these digests separately after a backup.

Persistent paths on Rinoa:

- `/home/danny/docker/actual/data` contains the Actual server and user files.
- `/home/danny/docker/paisa/data` contains the Paisa configuration and database.
- `/home/danny/git/ledger` contains the Ledger checkout.

The module refuses to start without these migrated paths.
The daily Ledger sync and monthly house valuation timers also move to Rinoa.
The sync uses the existing SOPS password and SSH identity.
A full Terra deployment no longer starts either finance stack.

Migration status and commands: [finance migration](finance-migration.md).

## Private Compose credentials

The Docker module creates each runtime `.env` file with mode `0600` before the service writes credentials.
It also repairs existing file permissions when the service starts.
This rule covers enabled container modules on both Rinoa and Vincent.

To repair existing files without a service restart, run:

```sh
ssh -t rinoa 'sudo find /var/lib/docker-containers -xdev -type f -name .env -exec chmod 0600 {} +' && ssh -t vincent 'sudo find /var/lib/docker-containers -xdev -type f -name .env -exec chmod 0600 {} +'
```

This command changes file permissions. It does not rotate credentials.

## Adding a New Service Checklist

After deploying a new container with Traefik labels, you must also add DNS records manually:

**Local domain** (`*.local.solivan.dev`): Add a custom DNS record in Pi-hole.
- Pi-hole admin → **Local DNS → DNS Records**
- Domain: `<subdomain>.local.solivan.dev` → IP: `192.168.1.110` (rinoa)

**Public domain** (`*.solivan.dev`): Add a DNS record in Cloudflare pointing to rinoa's WAN IP or Cloudflare Tunnel.
