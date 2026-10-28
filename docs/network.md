# Network Topology

LAN: `192.168.1.0/24`. Netgear R7800 router at `192.168.1.1`, Pi-hole DNS at `192.168.1.101`.

## Hypervisors (Proxmox)

| Host | IP | Web UI | Hosts (VMs) |
|---|---|---|---|
| **Locke** | 192.168.1.188 | https://192.168.1.188:8006 | mog, vincent, barrett, aerith, garnet |
| **Valefor** | 192.168.1.119 | https://192.168.1.119:8006 | rinoa (yuffie stopped) |

Locke and Valefor are separate standalone Proxmox nodes.
Both accept key-based SSH as root:

```sh
ssh root@192.168.1.188
ssh root@192.168.1.119
```

The local SSH configuration selects `danny` for bare hostnames. Use the explicit root account for hypervisor access.

### VM placement

VM IDs are local to each hypervisor.

| Hypervisor | VM ID | Name | Bridges |
|---|---|---|---|
| Locke | 100 | mog | vmbr0, vmbr2 |
| Locke | 102 | barrett | vmbr0 |
| Locke | 103 | garnet | vmbr0 |
| Locke | 104 | vincent | vmbr0 |
| Locke | 105 | aerith | vmbr1 |
| Valefor | 100 | yuffie (stopped) | vmbr0 |
| Valefor | 101 | rinoa | vmbr0 |

### Bridges and physical interfaces

| Hypervisor | Bridge | Physical port | Host address | Guest connections |
|---|---|---|---|---|
| Locke | vmbr0 | enp5s0 | 192.168.1.188/24 | Mog, Barrett, Garnet, Vincent |
| Locke | vmbr1 | enp6s0f0 | none | Aerith |
| Locke | vmbr2 | enp6s0f1 | none | Mog's second interface |
| Valefor | vmbr0 | enp1s0 | 192.168.1.119/24 | Rinoa, Yuffie |

Both management bridges use gateway `192.168.1.1`.
Locke's bridges use untagged VLAN 1. Physical switch connections are not documented.
Valefor's management bridge MAC is `68:1d:ef:3a:f0:75`.

### Locke storage

Locke has one NVMe (VG `pve`, no free extents): `pve/root` 96 GiB (`local`: ISOs, vzdump backups), `pve/swap` 2 GiB, and the thin pool `pve/data` 370.82 GiB (`local-lvm`).
Mog's six 8 TB data disks are passed through (`backup=0`) and are not in the pool.

| VM | local-lvm disk | Discard |
|---|---|---|
| mog | 25 GiB | on |
| barrett | 40 GiB | on |
| garnet | 93 GiB | on |
| vincent | 100 GiB | on |
| aerith | 112 GiB | on |
| **Promised** | **370 GiB** (pool 370.82 GiB) | |

Rules: the pool is not overcommitted. Before adding or growing a disk, shrink another by the same amount.
Do not take Proxmox snapshots on `local-lvm`; they use pool space beyond the disk sizes. Use `vzdump` to `local` instead.
`locke-pool-alert.timer` (from `scripts/locke-pool-alert.sh`, installed by hand) sends a Gotify `host-alerts` message when pool data or metadata reaches 90 %.
Shrink procedure and history: [plan 002](exec-plans/active/002-locke-zero-overcommit.plan.md).

### Management access

Locke's Proxmox firewall is enabled. Its IPv4 management IPSet permits the entire `192.168.1.0/24` subnet.
The allowed management TCP ports are 22, 8006, 3128, 5900–5999, and 60000–60050.
Its IPv6 management IPSet is empty.
Valefor's Proxmox firewall is disabled; its IPv4 and IPv6 iptables policies accept traffic.

Traefik on Rinoa proxies `locke.local.solivan.dev` and `valefor.local.solivan.dev` to the hypervisors' HTTPS port 8006.
These names resolve to Rinoa, not to the hypervisors. Direct hypervisor SSH uses the addresses listed above.
Neither Traefik management route has an IP allowlist. Traefik's global `serversTransport.insecureSkipVerify` value is `true`.
Cloudflare tunnel ingress configuration resides outside this repository.

## VMs and physical NixOS hosts

| Host | IP | Role | Runs on |
|---|---|---|---|
| **rinoa** | 192.168.1.110 | Docker host: **Traefik reverse proxy**, Prowlarr, Immich, CrowdSec, Obsidian LiveSync, BookOrbit | Valefor |
| **mog** | 192.168.1.167 | SMB file server | Locke |
| **vincent** | 192.168.1.185 | CI/CD runner (Forgejo/GitHub runner), Uptime Kuma (3001), Gotify (8070) | Locke |
| **barrett** | 192.168.1.112 (reserved) | VPN torrent server (qBittorrent + NordVPN) | Locke |
| **aerith** | 192.168.1.118 | Plex media server | Locke (VM 105) |
| **terra** | 192.168.1.173 (Wi-Fi DHCP; MAC `8c:86:dd:77:63:28`) | Ubuntu LLM inference server, pyinfra-managed | bare metal, not a VM |

Barrett's `ens18` has `192.168.1.112`. Its former `192.168.1.117` address no longer responds.
The router reserves `192.168.1.112` for Barrett's MAC `bc:24:11:39:96:98`.
The repository's `IfupdownNetworkModule` configures ifupdown/dhcpcd and excludes the interface from NetworkManager management.

## Reverse proxy dependency

Rinoa runs Traefik, which fronts the routed `*.local.solivan.dev` and `*.solivan.dev` services (see [Docker](docker.md)).
These routes depend on Rinoa and its hypervisor, Valefor, even when the backend runs on another host.
Direct backend connections use the backend's own IP address and service port.

## Terra network connection

Terra uses a USB `rtw88_8822bu` Wi-Fi adapter. Its wired interface is `enp4s0`.
The `wifi-watchdog.timer` reloads the driver and reconnects after three minutes without gateway connectivity.

## Traffic paths and Suricata visibility

Live route and packet checks on 2026-10-24 showed these paths:

| Traffic | Path |
|---|---|
| Ordinary internet access | Client → R7800 (`192.168.1.1`) → internet |
| Public services through Cloudflare Tunnel | Rinoa establishes outbound UDP 7844 connections to Cloudflare, which carries incoming service requests |
| Reverse proxy | Rinoa Traefik → Docker backend or another LAN host |
| Barrett internet access | Policy routing table 205 → `nordlynx` → NordVPN server, through the R7800 |
| Barrett LAN access | `ens18` → LAN destination, outside `nordlynx` |
| Aerith storage access | Aerith → Mog over SMB (TCP 445), outside Traefik |

Barrett used NordVPN endpoint `103.219.20.242` during this check. The endpoint can change.
The qBittorrent backend responded at `192.168.1.112:8112`. The old `.117:8112` backend timed out.
Terra reported Tailscale logged out. Headscale reported no registered nodes at the time of the check.

Rinoa has one virtual interface, `ens18`, attached to Valefor's `vmbr0` through its VM firewall bridge.
Valefor has one active physical Ethernet interface, `enp1s0`.
Neither Valefor's uplink nor Rinoa's VM interface received a controlled Terra-to-internet ICMP test.
Some unrelated SMB packets reached Valefor, but this does not establish complete traffic visibility.

Rinoa's active Suricata configuration monitors its own `ens18` traffic only.
The implemented [distributed security stack](security.md) selects central services on Vincent and local sensors on both VMs.
Each sensor needs mirrored traffic from its own hypervisor for wider coverage.
A switch mirror port must receive both traffic directions and connect to a dedicated capture interface for the local sensor VM.
The capture interface must have no IP address, default route, or forwarding role.
Mirroring the router uplink covers routed internet traffic. LAN-to-LAN traffic needs the relevant switch ports mirrored too.
Wi-Fi traffic switched within the R7800 can require capture on the router itself.
The router's SSH port refused connections during this check. Switch models and physical port connections remain unknown.

Both sensor VMs must run Suricata passively. It must preserve routing, VPN interfaces, NAT, and firewall rules.
Encrypted HTTPS and VPN payloads remain encrypted at the sensor.


## One-time Proxmox capture setup

**Status: not applied.** Neither hypervisor has a capture NIC or mirror feed configured.
These are native Proxmox networking settings, performed once and documented here after application.
The guest security services remain managed through Nix.
No security application or agent runs directly on a hypervisor.

Before changes, save each VM configuration, bridge/firewall topology, and existing `tc` filters.
Preserve every existing bridge, production NIC, management address, default route, and unrelated filter.
Locke's three physical ports are all in use. Do not pass them through to Vincent.

Add an isolated virtual capture NIC to Vincent VM 104 and Rinoa VM 101.
Keep each capture link disconnected until guest DHCP, addressing, and forwarding are disabled.
Use the package's `captureInterfaces` option for the actual guest NIC name.
Block capture-NIC egress into production at the hypervisor too.

Mirror packet copies from both directions of the selected physical and guest paths.
Use native `tc mirred ... mirror` settings; never redirect production packets through a sensor.
Include guest paths that remain inside a bridge, including any Proxmox firewall bridges.
Exclude capture destinations from mirror sources to prevent loops and duplicate feeds.
Preserve unrelated qdiscs and filters.

Native persistence must restore owned filters after boot and VM tap recreation.
Before application, record the exact persistence mechanism and its owned rollback commands.
A sensor outage must leave production traffic flowing normally.

Record these values here when the settings are applied:

| Setting | Locke / Vincent | Valefor / Rinoa |
|---|---|---|
| Added VM NIC ID and MAC | Pending | Pending |
| Guest capture interface | Pending | Pending |
| Isolated capture bridge/tap | Pending | Pending |
| Physical sources | enp5s0, enp6s0f0, enp6s0f1 | enp1s0 |
| Guest sources and directions | Pending | Pending |
| Owned filter handles/priorities | Pending | Pending |
| Persistence configuration | Pending | Pending |
| Backup and exact rollback commands | Pending | Pending |
| Bidirectional packet and egress-isolation checks | Pending | Pending |
| Tap recreation and boot persistence checks | Pending | Pending |

Check mirror counters and bounded packet samples before claiming coverage.
Check addresslessness, blocked capture egress, VPN access, storage, and reverse-proxy access.
Check tap recreation on isolated temporary interfaces first.
Observe production reboot persistence during normal maintenance; do not reboot working hypervisors solely for this check.
Remove only owned settings during rollback.

| Coverage path | Current evidence |
|---|---|
| Sensor VM's own interface | Controlled packet detection passed on Terra; both production stacks healthy |
| Same-hypervisor guest traffic | No mirror configured |
| Hypervisor physical ports | No mirror configured |
| Other LAN clients and ordinary internet traffic | Router/switch feed required |

A router/switch feed is separate from these Proxmox settings.
Switch models and physical port connections still need identification before designing that feed.
