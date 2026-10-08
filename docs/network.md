# Network Topology

LAN: `192.168.1.0/24`. Router at `192.168.1.1`, Pi-hole DNS at `192.168.1.101`.

## Hypervisors (Proxmox)

| Host | IP | Web UI | Hosts (VMs) |
|---|---|---|---|
| **Locke** | 192.168.1.188 | https://192.168.1.188:8006 | mog, vincent, barrett |
| **Valefor** | 192.168.1.119 | https://192.168.1.119:8006 | rinoa |

Proxmox web UI (port 8006) is a more reliable up/down check than ICMP ping —
both hosts have shown ICMP filtered/blocked while 8006 answered fine.

## VMs and physical NixOS hosts

| Host | IP | Role | Runs on |
|---|---|---|---|
| **rinoa** | 192.168.1.110 | Docker host: **Traefik reverse proxy**, Prowlarr, Immich, CrowdSec, Obsidian LiveSync, BookOrbit | Valefor |
| **mog** | 192.168.1.167 | SMB file server | Locke |
| **vincent** | 192.168.1.185 | CI/CD runner (Forgejo/GitHub runner), Uptime Kuma (3001) | Locke |
| **barrett** | ~~192.168.1.114~~ **192.168.1.112** | VPN torrent server (qBittorrent + NordVPN) | Locke |
| **aerith** | 192.168.1.118 | Plex media server | hypervisor unknown — not yet confirmed |
| **terra** | 192.168.1.173 (Wi-Fi DHCP; MAC `8c:86:dd:77:63:28`) | Ubuntu LLM inference server, pyinfra-managed | bare metal, not a VM |

⚠ **Known drift**: `hosts/nixos/vincent/default.nix` monitors Barrett at
`192.168.1.114`, but Barrett has actually been observed on DHCP at
`192.168.1.112`. The monitor config should either be updated to the real IP
or Barrett should be pinned to a static/reserved lease.

## Why Rinoa matters most for "is anything routed broken"

Rinoa runs Traefik, which fronts all `*.local.solivan.dev` and
`*.solivan.dev` routed services (see `docs/docker.md`). If Rinoa (or its
hypervisor, Valefor) is down, every routed URL breaks even if the backend
service itself (e.g. Vincent, Mog) is healthy and reachable directly by IP.
Always check direct-IP:port reachability of the backend *and* Rinoa/Traefik
separately before concluding a service itself is down.

## Diagnostic order for "host X is unreachable"

1. `ping` — cheap, but several hosts here have ICMP filtered even when up.
2. Direct TCP check of a known service port (SSH 22, Proxmox 8006, SMB 445,
   app-specific ports from `hosts/nixos/vincent/default.nix`'s monitoring
   list) — more reliable than ping.
3. `arp -a` on a LAN-local machine — an `(incomplete)` entry (no MAC learned)
   means the box isn't answering ARP at all, which usually means it's
   powered off, unplugged, or its uplink is down — not a software/firewall
   issue on the box itself.
4. If the box is a Proxmox VM and its hypervisor is also unreachable by all
   of the above, check the hypervisor's physical network link first
   (switch/cable) before assuming the VM guest OS itself is broken — a
   hypervisor uplink failure (missing switch-to-router cable, dead port)
   takes down every VM on it and looks identical to "VM is down" from the
   LAN side.
