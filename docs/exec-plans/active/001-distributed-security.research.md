# Research: Distributed security on Vincent and Rinoa

**ID:** 001
**Date:** 2026-10-25
**Issue/Ref:** Reuse existing VMs for one Nix-enabled security package; distribute sensors without installing security applications on Proxmox.
**Status:** complete

## Summary

The repository contains a tested Suricata/EveBox/Gotify prototype, not the requested distributed security package.
Vincent will host central analysis and a local sensor; Rinoa will host a remote sensor and retain CrowdSec for Traefik.
Both Proxmox hosts need capture networking and persistent packet mirroring, with no new VMs or security applications.
Use one shared Nix module with central/sensor roles and a Compose stack per guest; keep Gotify separate.
The package and mirrored feeds are proposed, not deployed.

## Repository orientation and relevant files

`flake.nix` and `lib/lib.nix` construct hosts from reusable `modules/`, host selections in `hosts/`, and Home Manager configuration in `home/`.
Other top-level areas include `docs/`, `scripts/`, `shared/`, `iso/`, and `windows/`.
NixOS services use Nix-generated runtime configuration and systemd-managed Compose projects; non-Nix Linux hosts use pyinfra.
The prototype has Python unittest coverage for its notification bridge and recorded Terra smoke tests.
There is no existing Proxmox deployment configuration to extend.

| File | Role |
|------|------|
| `modules/nixos/services/docker/default.nix` | Imports container modules, including the disabled Suricata prototype; exposes shared Docker infrastructure and health checks. |
| `modules/nixos/services/docker/containers/suricata/default.nix` | Current `enable`, singular `interface`, and `gotifyTokenFile` options; creates Compose unit and maintenance timer. |
| `modules/nixos/services/docker/containers/suricata/docker-compose.yml` | Local Suricata, EveBox, and notification bridge; no Wazuh or remote forwarding. |
| `modules/nixos/services/docker/containers/suricata/evebox.yaml` | SQLite event storage, local EVE ingestion, seven-day/4 GB retention. |
| `modules/nixos/services/docker/containers/suricata/gotify_bridge.py` | Reads EVE alerts and sends Gotify notifications with persistent positions. |
| `modules/nixos/services/docker/containers/suricata/test_gotify_bridge.py` | Bridge unit tests to retain when reorganizing the package. |
| `modules/nixos/security/sops/suricata.yaml` | Existing encrypted notification token; never copy plaintext into Nix output. |
| `hosts/nixos/vincent/default.nix` | Central host selection, existing Gotify, runners, and readiness checks. |
| `hosts/nixos/rinoa/default.nix` | Remote sensor host selection, existing Traefik/CrowdSec, and readiness checks. |
| `modules/nixos/services/docker/containers/crowdsec/` | Existing independent reverse-proxy protection; pending acquisition, key, and trusted-client fixes. |
| `modules/nixos/services/docker/containers/traefik/config/config.yml` | Pending Headscale access-range additions; central UI routing will also need this cross-host configuration. |
| `docs/security.md`, `docs/network.md`, `docs/docker.md` | Intended architecture, observed topology, prototype test history, and deployment notes. |

## Current actual state

Repository inspection confirms neither Vincent nor Rinoa enables the prototype.
There is no distributed-role module, Wazuh configuration, remote forwarding, capture-NIC configuration, or Proxmox mirror configuration.
The earlier Rinoa staging snapshot is superseded and must not be activated.

Read-only live findings supplied by the coordinating agent:

| System | Observed state |
|--------|----------------|
| Locke `192.168.1.188` | Root SSH works; no `clsact` qdisc; physical `enp5s0` serves `vmbr0`, `enp6s0f0` serves Aerith through `vmbr1`, `enp6s0f1` serves Mog through `vmbr2`. |
| Vincent `192.168.1.185` | VM 104 on Locke; only `net0` on `vmbr0`; 12 vCPU/32 GiB, approximately 30 GiB RAM and 58 GiB disk free; no security-stack containers. |
| Valefor `192.168.1.119` | Root SSH works; no `clsact` qdisc; physical `enp1s0` serves `vmbr0`. |
| Rinoa `192.168.1.110` | VM 101 on Valefor; only `net0` on `vmbr0`; 4 vCPU/12 GiB; live CrowdSec, bouncer, and Traefik; no Suricata/EveBox/Wazuh containers. |

The prototype passed Terra smoke tests and was removed afterward; this does not prove the distributed package works.
CrowdSec fixes exist in the working tree but are not deployed.
Passwordless sudo fails on both NixOS guests; authenticated guest activation remains necessary.

## Data / Control Flow

Current: `flake.nix` → NixOS module imports → host enablement → systemd Compose unit → containers and persistent volumes.
Enabling the prototype currently reads one guest interface with host networking, writes EVE records, and feeds local EveBox plus Gotify.

Proposed: hypervisor physical/guest interfaces → copied packets → unnumbered guest capture NIC → Suricata EVE volume.
Local EVE records feed central EveBox directly or through a remote EveBox agent, Wazuh log collection, and the existing notification bridge.
Wazuh agents initially collect Suricata logs only; full guest monitoring is outside this first package.
CrowdSec separately reads Traefik logs and enforces decisions only through selected reverse-proxy middleware.

## Root Cause / Insertion Point

The missing work is implementation, not enablement of an already complete module.
Evolve the prototype into the shared package under `modules/nixos/services/docker/containers/`, register its import, and select roles in the two existing host files.
Preserve the repository's systemd/Compose/SOPS lifecycle rather than introducing another orchestrator.
Proxmox networking will use one-time host settings, as requested by the user; record exact settings and restoration commands in `docs/network.md`.
Do not introduce Proxmox Nix/pyinfra modules or deployment entrypoints.

## Recommended Approach

Expose `modules.nixos.docker.containers.security-stack` with `enable`, `role`, a nonempty `interfaces` list, and `serverAddress` defaulting to Vincent's `192.168.1.185`.
The central role includes Suricata, EveBox, Wazuh manager/indexer/dashboard, and notifications; the sensor role includes Suricata, EveBox forwarding, Wazuh collection, and notifications.
Persist logs, credentials, certificates, databases, agent registration, and forwarding positions separately.
Use pinned upstream Wazuh single-node Compose conventions and authenticated sensor transport; disable active response and keep Suricata passive.
Generate credentials rather than retaining sample accounts; keep secrets and certificates outside the Nix store and restrict manager/indexer APIs to the stack.

Start with local `ens18` capture. Give each VM an additional capture interface with no address or route, retaining its management NIC.
Mirror packet copies from relevant physical and guest paths, accounting for both directions, guest firewall bridge paths, duplicate capture, and dynamically recreated tap interfaces.
Apply native Proxmox settings once through root SSH; document their persistence and owned rollback without creating a new deployment system.
Prevent DHCP, guest packet egress, and forwarding on capture links; add the capture interfaces to Suricata only after validating their isolation.
Test event delivery before adding mirrors, then verify LAN, Headscale, NordVPN, storage, and proxy access with sensors running and stopped.
Test lifecycle behavior on isolated temporary interfaces and inspect native persistence settings; record unobserved production VM stop/start or hypervisor reboot behavior as not proven without disrupting services.

## Risks & Non-Obvious Dependencies

- Wazuh's documented Docker baseline includes 50 GB storage; Vincent has only about 58 GiB free shared with existing services. Define retention and measure actual growth before claiming capacity. Its indexer also requires `vm.max_map_count` of at least 262144 and generated certificates. [Wazuh Docker deployment](https://documentation.wazuh.com/current/deployment-options/docker/wazuh-container.html)
- Vincent's current `vm.max_map_count` is 1048576 according to the coordinating agent's live check; preserve it rather than lowering it to the documented minimum.
- Wazuh reads Suricata JSON from `eve.json`; a container collecting that file does not thereby monitor the guest filesystem or authentication logs. [Wazuh Suricata integration](https://documentation.wazuh.com/current/proof-of-concept-guide/integrate-network-ids-suricata.html)
- EveBox supports shipping EVE files to a central server; forwarding state and sensor identity must survive restarts. [EveBox agent](https://evebox.org/docs/agent/)
- Linux `mirred` distinguishes copying from redirecting. Use `mirror`; incorrect redirection could interrupt production traffic. [Linux mirroring manual](https://man7.org/linux/man-pages/man8/tc-mirred.8.html)
- Ports already serve production bridges. PCI passthrough would remove those ports from existing guests; keep bridge membership unchanged.
- Mirroring both physical and guest paths can duplicate packets or create loops if the destination is included as a source. Prove one capture topology before expanding it.
- Hypervisor mirrors cover packets traversing those hypervisors, not all router/Wi-Fi traffic. VPN payloads and HTTPS remain encrypted at these capture points.
- A final coverage matrix must distinguish host-local, same-host VM, inter-host, and encrypted VPN traffic from blind spots such as Terra-to-internet traffic. Router SSH currently refuses connections.
- CrowdSec client attribution through Cloudflare Tunnel is unresolved; do not trust arbitrary forwarded headers or promise public-client blocking yet.

## Rejected Approaches

| Approach | Why rejected |
|----------|--------------|
| Dedicated security VM | User explicitly chose existing Vincent and Rinoa. |
| Security applications on Proxmox | User explicitly permits networking configuration only. |
| Central-only capture | Misses traffic local to Valefor and some guest paths. |
| NIC passthrough or inline routing | Displaces active bridges or introduces availability dependencies. |
| Independent host-specific stacks | Duplicates configuration and prevents simple role-based enablement. |

## Open Questions

- [ ] Select persistent mirror lifecycle handling for VM starts/stops and tap recreation; inspect Proxmox firewall topology before choosing targets.
- [ ] Measure disk growth and set retention limits for Suricata, EveBox, and Wazuh within Vincent's existing capacity.
- [ ] Validate exact pinned images, certificate bootstrap, authenticated forwarding, and agent reconnect behavior on Terra.
- [ ] Establish an authenticated guest activation method; existing root hypervisor SSH does not establish guest sudo authorization.
- [ ] Determine whether extra router/switch feeds are needed after proving server traffic coverage.
