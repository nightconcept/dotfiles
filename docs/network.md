# Network Topology

LAN: `192.168.1.0/24`. Router at `192.168.1.1`, Pi-hole DNS at `192.168.1.101`.

## Hypervisors (Proxmox)

| Host | IP | Web UI | Hosts (VMs) |
|---|---|---|---|
| **Locke** | 192.168.1.188 | https://192.168.1.188:8006 | mog, vincent, barrett, aerith (garnet stopped) |
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
| Locke | 103 | garnet (stopped) | vmbr0 |
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
| **barrett** | 192.168.1.112 (reserved), 192.168.1.117 | VPN torrent server (qBittorrent + NordVPN) | Locke |
| **aerith** | 192.168.1.118 | Plex media server | Locke (VM 105) |
| **terra** | 192.168.1.173 (Wi-Fi DHCP; MAC `8c:86:dd:77:63:28`) | Ubuntu LLM inference server, pyinfra-managed | bare metal, not a VM |

Barrett's `ens18` currently has both `192.168.1.112` and `192.168.1.117`.
The router reserves `192.168.1.112` for Barrett's MAC `bc:24:11:39:96:98`.
The repository's `IfupdownNetworkModule` configures ifupdown/dhcpcd and excludes the interface from NetworkManager management.

## Reverse proxy dependency

Rinoa runs Traefik, which fronts the routed `*.local.solivan.dev` and `*.solivan.dev` services (see [Docker](docker.md)).
These routes depend on Rinoa and its hypervisor, Valefor, even when the backend runs on another host.
Direct backend connections use the backend's own IP address and service port.

## Terra network connection

Terra uses a USB `rtw88_8822bu` Wi-Fi adapter. Its wired interface is `enp4s0`.
The `wifi-watchdog.timer` reloads the driver and reconnects after three minutes without gateway connectivity.
