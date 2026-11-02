# Execution Plan: Storage locality and Aerith capacity

Status: active — Phases 0, 1 and 3 done 2026-11-01; Phase 2 (private network) and Phase 4 pending
Last reviewed: 2026-11-01
Owner: danny

**Research:** [Measurements and sources](003-storage-locality.research.md)
**Issue/Ref:** User investigation of slow `https://forge.solivan.dev/nightconcept/zekrom`.

## Goal

Reduce storage latency and SMB traffic across physical Ethernet links.
Keep active application databases and Git repositories on local storage.
Use an internal Locke storage network for media and download services.
Resolve Aerith capacity before any application migration.

This session changed documentation only. No deployment, data migration, network change, or service restart occurred.
Future sessions must refresh measurements before execution.

## Worker context bootstrap

Read these files before implementation:

1. `AGENTS.md` and applicable `CLAUDE.md` files.
2. This plan and its research document.
3. `docs/network.md`, `docs/docker.md`, and `docs/architecture.md`.
4. `docs/exec-plans/active/002-locke-zero-overcommit.plan.md`.
5. The host and module files listed in the applicable phase.

The plan skill references `docs/repo/index.md` and `docs/exec-plans/tech-debt.md`.
Neither file exists at plan creation. Use the existing documentation hub instead.

The working tree contains unrelated changes, including Rinoa and Traefik configuration.
Preserve these changes. Record `git status --short` before edits.
Do not overwrite configuration from this plan without reading its current contents.

## Decisions and user constraints

- BookOrbit and its database stay on Rinoa.
- Audiobookshelf and LibbyRip converter stay on Rinoa.
- Plex stays on Aerith.
- Traefik and Cloudflare Tunnel stay on Rinoa.
- Mog remains the storage VM. Application placement on Mog is outside this plan.
- Vincent retains CI runners, monitoring, and central security services.
- Barrett retains VPN download services and their existing VPN protection.
- Aerith migration remains conditional on an explicit storage-capacity decision.
- No implementation is authorized by this documentation-only request.

## Evidence and interpretation

Measurements below describe live services on 2026-11-01. They are approximate snapshots.
Allocated directory sizes can differ between SMB and Mog-local measurements.
The Forgejo totals below use Mog-local `du` results.

Forgejo logged a Zekrom request that returned HTTP 500 after 57.7 seconds.
A ten-minute sample contained 53 HTTP 500 responses and 140 slow-request warnings.
Rinoa load reached 22 on four vCPUs. Git processes entered uninterruptible I/O wait.

A later ten-second sample recorded about 908 SMB operations per second.
These operations mainly opened files, closed files, and queried metadata.
Only 145 KB of payload arrived during that sample.
This supports metadata latency as a concern. It does not prove physical disk bandwidth saturation.

Jellyfin read 367 MB through system calls during another ten-second sample.
Most reads used cached data. This figure does not measure SMB transfer volume.
Jellyfin logs showed an active library scan and repeated media-probe errors.
Live Git activity included fetches, pushes, and `pack-objects` for `nightconcept/porygon2`.
Earlier Forgejo logs included history, diff, and blame requests.

Most recent Forgejo HTTP requests were Actions runner polling.
The proxy logs omit user agents and show tunnel traffic under a shared Docker address.
The original requesting machine remains unknown. Do not label this traffic an attack without additional evidence.
The samples do not assign every SMB operation to a specific service.

## Measured storage

### Forgejo on Rinoa

| Component | Current location | Allocated size |
|---|---|---:|
| Git repositories | Titan `/docker/forgejo/git/repositories` | 1.93 GiB |
| Git LFS | Titan `/docker/forgejo/git/lfs` | 0.44 GiB |
| Generated repository archives | Titan `/docker/forgejo/gitea/repo-archive` | 1.99 GiB |
| Actions artifacts | Titan `/docker/forgejo/gitea/actions_artifacts` | 0.85 GiB |
| Packages | Titan `/docker/forgejo/gitea/packages` | 0.30 GiB |
| Attachments | Titan `/docker/forgejo/gitea/attachments` | 0.22 GiB |
| Other application state | Titan, within the same `/data` tree | Small |
| **Entire `/data` tree** | **`/mnt/titan/docker/forgejo`** | **5.74 GiB** |
| PostgreSQL data directory | Rinoa `/var/lib/docker-containers/forgejo/db` | 106 MiB |
| Forgejo logical database | Within the PostgreSQL directory above | 38 MiB |

Forgejo contains 108 repositories. Repository sizes recorded in its database can differ from actual disk allocation.
The largest measured directories were `metamon.git` at 714 MiB and `sdl3-cs.git` at 349 MiB.
`zekrom.git` used 724 KiB. Its small size does not explain the request delay.
Rinoa had about 106 GiB available before migration.

Mog exports `/srv/mergerfs/pool0/titan/` as the Titan share.
Prefer server-local size measurements over repeated recursive SMB scans.
Generated archives are potential cleanup candidates, but this plan requires no deletion to fit Forgejo locally.

### Proposed Aerith applications

| Service | Current local state path on Rinoa | Allocated size |
|---|---|---:|
| Jellyfin | `/var/lib/docker-containers/jellyfin/config` | 12.27 GiB |
| Sonarr | `/home/danny/docker/sonarr/config` | 1.07 GiB |
| Sonarr Anime | `/home/danny/docker/sonarr-anime/config` | 0.30 GiB |
| Radarr | `/home/danny/docker/radarr/config` | 2.45 GiB |
| **Total application state** | | **16.09 GiB** |

Jellyfin metadata occupies about 11.10 GiB. Its remaining state includes databases and other application files.
These figures exclude media on Titan, container images, image downloads, and additional rollback copies.
Download sweeper has no material application database measured in this investigation.

### Capacity limits

| Host or VM | Observed capacity |
|---|---|
| Aerith | 112 GiB virtual disk, about 110 GiB root filesystem, 39.84 GiB available |
| Existing Plex state | 39.43 GiB at `/var/lib/plex` |
| Aerith after proposed state transfer | About 23.75 GiB available, before images and future growth |
| Aerith memory | 16 GiB assigned, about 14 GiB available during the sample |
| Locke memory | About 125 GiB total, 29 GiB available during the sample |
| Locke thin pool | 370.82 GiB, about 69.92% physical allocation |
| Total promised VM disks | 370 GiB, with no free VG extents |

Free thin-pool blocks do not represent permission to allocate larger VM disks.
The repository prohibits pool overcommit and Proxmox snapshots on `local-lvm`.
Any disk growth needs matching capacity recovery or additional physical storage.
Plex metadata already dominates Aerith usage. Current free space does not establish sufficient long-term capacity.

## Target placement

| Host | Service placement | Data arrangement |
|---|---|---|
| Rinoa | Forgejo and PostgreSQL | Move all Forgejo `/data` to local disk. Keep PostgreSQL local. |
| Rinoa | Obsidian LiveSync | Move CouchDB data from Titan to local disk. Measured size: about 81.5 MiB. |
| Rinoa | BookOrbit, Audiobookshelf, LibbyRip converter | Stay. Preserve media paths and service URLs. |
| Rinoa | Traefik, tunnel, web applications, indexers, Recyclarr, Seerr | Stay. Update connections to moved services. |
| Aerith | Plex | Stay. Mount Titan through the private storage network. |
| Aerith, conditional | Jellyfin, Sonarr, Sonarr Anime, Radarr, download sweeper | Local application state. Media and downloads remain on Titan. |
| Barrett | qBittorrent and SABnzbd | Stay. Add private Titan access without changing VPN protection. |
| Mog | Samba, mergerfs, storage administration | Stay. Add a private storage address and preserve LAN access. |
| Vincent | Runners, monitoring, central security | Stay. Update monitors for moved services. |

## Network design

Current placement on Locke:

- Mog VM 100: `net0` on `vmbr0`, `net1` on `vmbr2`.
- Aerith VM 105: `net0` on `vmbr1`.
- Barrett VM 102: LAN NIC on `vmbr0`.

Each existing bridge has a different physical Ethernet port.
Aerith learns the Mog MAC through the physical uplink.
Traffic between these guests currently traverses the external network despite their shared hypervisor.

Mog has two interfaces on `192.168.1.0/24` with equal route metrics.
Its addresses were `.167` and `.201`. Route selection used the second NIC during the investigation.
ARP responses for `.167` used the second NIC MAC in the Aerith observation.
Treat this ambiguity separately from application migration.

Proposed private network, subject to collision checks:

- Bridge: `vmbr3`, with no physical port, host address, or gateway.
- Subnet: `10.77.0.0/24`.
- Mog: `10.77.0.10/24`.
- Aerith: `10.77.0.20/24`.
- Barrett: `10.77.0.30/24`.
- Guest NIC model: VirtIO. Record actual interface names and MAC addresses.

Preserve every existing LAN NIC, default route, and service address.
Disable DHCP, IPv6 autoconfiguration, and forwarding on the new storage interfaces.
Do not expose the private bridge through NAT or the public tunnel.
Limit private guest access to required storage traffic.
Update Samba access rules for the private subnet without exposing additional shares.

Aerith and Barrett retain `/mnt/titan` as their mount path.
Their share source becomes `//10.77.0.10/titan`.
Rinoa and other external consumers continue to use `//192.168.1.167/titan`.
Rinoa Traefik continues to reach Aerith through `192.168.1.118`.
No gateway or forwarding between Aerith interfaces is necessary.

## Phases

### Phase 0: Refresh evidence and decide Aerith capacity

**Depends on:** none.
**Status:** [x] done 2026-11-01.

**Files:** This plan and its research document.

1. Record the current working tree and deployed versions.
2. Refresh `df`, `du`, container mounts, pool allocation, VM disk sizes, and available memory.
3. Measure Docker image space and temporary copy space.
4. Record existing alert thresholds and metadata retention policies.
5. Select the Aerith capacity option with the user before application migration.

Recommended capacity options:

- Add dedicated SSD capacity for Aerith application state, with its own backup coverage.
- Reallocate existing VM disk capacity only through a separately reviewed shrink and recovery procedure.
- Keep the media applications on Rinoa until additional capacity exists.

Proposed planning reserve: retain at least 30 GiB available on Aerith after state, images, and temporary files.
This reserve is a recommendation, not a previously approved policy or a growth forecast.
Today's 23.75 GiB projection fails this proposed reserve before image overhead.
The user must choose the reserve and capacity strategy from concrete refreshed measurements.
Do not assume cleanup will provide permanent capacity.

**Checks:**

```bash
git status --short
ssh root@192.168.1.188 'lvs -o lv_name,lv_size,data_percent,metadata_percent; pvesm status; qm list'
ssh aerith 'df -k /; du -sk /var/lib/plex'
ssh rinoa 'df -k /; docker system df'
```

**Exit condition:** Record the capacity decision and its arithmetic in this file.
**Rollback:** No production changes occur in this phase.

### Phase 1: Remove active application state from SMB on Rinoa

**Depends on:** refreshed evidence. Independent of the Aerith capacity decision.
**Status:** [x] done 2026-11-01.

**Files to change:**

- `hosts/nixos/rinoa/default.nix`: set Forgejo `remoteDataPath` to `/var/lib/docker-containers/forgejo/data`.
- `modules/nixos/services/docker/containers/obsidian-livesync/default.nix`: expose a local data-path option if absent.
- Its compose file: consume the selected data path instead of a fixed Titan path.
- `hosts/nixos/rinoa/default.nix`: select local CouchDB storage.
- This plan: record backup and migration results.

Keep the Forgejo option name for compatibility unless a separate refactor becomes necessary.
Preserve signing keys, Git hooks, attachments, LFS, packages, artifacts, and application identity.
Do not print `.env`, application configuration secrets, credentials, or database passwords.

Use a consistent application backup and a paused writer for the final copy.
For CouchDB, use a supported backup or stop CouchDB before the final filesystem copy.
Preserve ownership, modes, symlinks, and timestamps.
Compare source and destination before the switch.
Keep the original directories intact and inactive through the rollback window.
Configure recurring backups to Titan and record a restore check.

**Checks:**

```bash
nix build .#nixosConfigurations.rinoa.config.system.build.toplevel --dry-run --impure
ssh rinoa 'docker inspect forgejo obsidian-livesync --format "{{.Name}} {{range .Mounts}}{{println .Source .Destination}}{{end}}"'
curl --fail --max-time 15 https://forge.solivan.dev/api/healthz
```

Also exercise an authenticated Zekrom read and a temporary repository push/fetch/delete cycle.
Keep authentication in memory or protected credential files.
Exercise an Obsidian client synchronization without disclosing document contents.
Record backups, ownership, database consistency, and final directory sizes.

**Rollback:** Stop the affected service and restore its previous path.
If the new instance accepted writes, copy those writes back while both instances remain stopped.
Never activate an obsolete source directory and silently discard newer writes.

### Phase 2: Add and prove the internal storage network

**Depends on:** Phase 0 network inventory. Independent of the Aerith disk decision.
**Status:** [ ] deferred. Mog network changes can interrupt Plex SMB sessions; apply when Plex is idle.

**Files and external configuration:**

- Locke native Proxmox bridge and guest NIC configuration.
- Mog native persistent network and Samba configuration.
- `modules/nixos/storage/network-drives/default.nix`: add a host-selectable Titan source with the existing default.
- `hosts/nixos/aerith/default.nix`: declare the private interface and select the private Titan source.
- `hosts/linux/barrett/main.py` and applicable network module: declare the private interface and storage route.
- `docs/network.md`: record bridge, addresses, MACs, persistence, and rollback commands.

Record exact native changes and backups before application.
Proxmox and Mog have no repository deployment entrypoints. Use their native persistent configuration.
Do not install application services on the hypervisor.
Do not remove or repurpose the existing Mog NICs during this phase.
Prepare exact rollback commands before a mount-source switch.

Pause consumers during each mount-source switch.
Do not allow media applications to scan an empty mount directory.
Keep the retained Rinoa services on their current LAN mount source.
For Barrett, allow private storage through VPN rules explicitly and preserve the kill switch.
Exercise a VPN disconnect check only during an agreed maintenance window.

**Checks:**

```bash
ssh root@192.168.1.188 'bridge link show; bridge fdb show br vmbr3'
ssh aerith 'ip route get 10.77.0.10; findmnt -t cifs; ping -n -c 10 10.77.0.10'
ssh barrett 'ip route get 10.77.0.10; findmnt -t cifs; nordvpn settings'
curl --fail --max-time 15 https://plex.local.solivan.dev/identity
```

Record bounded packet captures on the virtual and physical interfaces during a known storage operation.
The private storage flow must remain on the virtual bridge.
Compare private-path RTT and representative metadata reads against the original LAN path.
Keep the original LAN paths functional for Rinoa, Traefik, and SSH.

**Rollback:** Restore each mount source, then restore saved native interface and bridge configuration.

### Phase 3: Prepare Aerith and migrate media applications in small batches

**Depends on:** Phase 0 capacity decision and Phase 2 network checks.
**Status:** [x] done 2026-11-01 (all services in one window).

**Files to change:**

- `hosts/nixos/aerith/default.nix`: enable Docker, moved services, readiness checks, and local application paths.
- `hosts/nixos/rinoa/default.nix`: remove moved services and their local readiness dependencies.
- `modules/nixos/services/docker/containers/traefik/config/config.yml`: add explicit Aerith backend routes.
- Relevant `jellyfin`, `sonarr`, `sonarr-anime`, and `radarr` modules and compose files: fix migration requirements only.
- `hosts/nixos/vincent/default.nix`: update direct service and aggregate readiness monitors.
- `docs/docker.md` and `docs/network.md`: update placement and backend addresses.

Use batches: Jellyfin first, then arr services, then download sweeper.
Keep only one active instance of each application and sweeper.
Preserve application identity, database state, API keys, library paths, and download-client mappings.
Update Prowlarr, Seerr, Recyclarr, and download-client connections to the moved services.
Preserve client-visible URLs and authentication middleware.
Rinoa Docker discovery cannot discover Aerith containers. Use the existing Traefik file provider.
Preserve LAN/public router names, TLS, CrowdSec protection, and service ports.

Review Jellyfin mount dependencies before first start.
Its current module lacks the hard Titan mount dependency needed to prevent scans against an empty directory.
Jellyfin UID was 911. Forgejo and arr ownership differ. Copy actual ownership rather than one global UID.
Preserve configured acceleration where present. Record CPU and RAM use during concurrent Plex and Jellyfin work.
Keep the bulk media and downloads on Titan.

**Checks:**

```bash
nix build .#nixosConfigurations.aerith.config.system.build.toplevel --dry-run --impure
nix build .#nixosConfigurations.rinoa.config.system.build.toplevel --dry-run --impure
nix build .#nixosConfigurations.vincent.config.system.build.toplevel --dry-run --impure
curl --fail --max-time 15 https://jellyfin.local.solivan.dev/health
curl --fail --max-time 15 https://sonarr.local.solivan.dev/ping
curl --fail --max-time 15 https://sonarr-anime.local.solivan.dev/ping
curl --fail --max-time 15 https://radarr.local.solivan.dev/ping
ssh aerith 'df -k /; free -h; systemctl --failed --no-pager'
```

Exercise existing Jellyfin playback and arr library access.
Exercise an agreed import without deleting media or disrupting an active download.
Record remaining disk space after images, state transfer, and normal operation.
Observe Plex and the retained Rinoa services throughout each batch.

**Rollback:** Stop the Aerith instance before restoring the Rinoa instance and proxy route.
Reconcile newer state before rollback. Retain an application-consistent backup for each batch.

### Phase 4: Reduce scans and measure the result

**Depends on:** applicable earlier phases.
**Status:** [ ] not started.

**Files:** Host configuration, network mount module where needed, monitoring configuration, and operational documentation.

Reduce repeated full scans and investigate Jellyfin probe errors.
Prefer targeted library updates from successful imports where supported.
Evaluate `actimeo=30` only on media mounts after baseline measurements.
Retain `cache=strict`. Record the delayed external-change visibility tradeoff.
Do not change all Titan consumers through an unscoped global mount adjustment.
Leave retained Rinoa applications in place.

Record metadata-operation rate separately from payload bandwidth.
Compare representative repository pages and private-path library access under normal load.
A private bridge reduces physical-network traffic, not the number of SMB operations.
Local Forgejo data removes SMB from its active repository path.

**Checks:**

```bash
ssh rinoa 'cat /proc/pressure/io; cat /proc/fs/cifs/Stats'
ssh aerith 'df -k /; cat /proc/pressure/io; cat /proc/fs/cifs/Stats'
curl -o /dev/null -sS --max-time 30 -w 'status=%{http_code} ttfb=%{time_starttransfer}\n' https://forge.solivan.dev/api/healthz
```

Repeat counters after a bounded interval under recorded workload conditions.
Use authenticated repository-page checks as well as health endpoints.
Document private-path packet evidence, application errors, capacity alerts, and rollback locations.
Use an observation period before removing old copies. The default proposal is seven days.
Do not remove source data as part of an unreviewed cleanup.

**Rollback:** Restore previous scan schedules and mount cache options independently.

## Testing and deployment strategy

Build each changed full host configuration before activation.
Use existing full-host rebuild or deployment commands from `AGENTS.md`.
Use `just barrett` only for the full Barrett deployment.
Do not add one-off deployment recipes.
Do not print secret-bearing files during diagnostics or validation.

Database and file migrations need read/write application checks, not health endpoints alone.
Persistent networking needs route, packet-path, LAN-access, and VPN checks.
Observe boot persistence during normal maintenance. Do not reboot healthy hosts only to test this plan.

The repository has no `just knowledge` or `just preflight` recipe at plan creation.
Use Markdown link and metadata checks for these documents.
Do not add unrelated documentation infrastructure.

## Known risks and unresolved decisions

- Aerith long-term capacity remains unresolved. Application migration waits for a recorded user decision.
- Growth rates and retention budgets remain unmeasured. Current sizes alone do not establish a growth forecast.
- Shared CPU and disk activity on Locke can still cause contention after network locality improves.
- Mog same-subnet NIC ambiguity remains outside the additive private-network phase.
- A separate change can simplify those existing NICs after client dependencies are documented.
- Rinoa retains some SMB activity because the user keeps three library services there.
- New local application state needs recurring backups and a restore check.
- Successful container health checks did not detect the original repository-page degradation.

## Out of scope

- Moving BookOrbit, Audiobookshelf, or LibbyRip converter off Rinoa.
- Moving every service onto Mog or Vincent.
- Adding a new VM or expanding the thin pool without a separate capacity design.
- Deleting Plex/Jellyfin metadata, Git archives, repositories, or old application copies automatically.
- Changing VPN protection, LAN management addresses, or existing reverse-proxy exposure.
- Implementing hypervisor traffic mirroring or unrelated security changes.

## Progress log and next-session starting point

- 2026-11-01: Completed live investigation and documentation. No production changes occurred.
- 2026-11-01: Recorded user exceptions and Aerith storage concern.
- Next session: read the bootstrap files, refresh Phase 0, then present concrete Aerith capacity choices.
- Forgejo local storage can proceed separately after implementation authorization.
- 2026-11-01: Capacity decision. `Plex Media Server.new` (20.9 GB, unchanged since 2024-03-24) was archived to Titan, verified with `tar --compare`, and deleted. Aerith had 55.5 GiB free before the move and 42 GiB after it, which meets the 30 GiB reserve.
- 2026-11-01: Cutover in one window, about 21:16–22:20 PST. No VM was shut down. Plex stayed active. Commit `7bbeff1`.
  - Forgejo `/data` moved to `/var/lib/docker-containers/forgejo/data` on Rinoa through a Mog tar. All files matched the Mog SHA-256 manifest. A Zekrom clone took 0.35 s.
  - CouchDB data moved to `/var/lib/docker-containers/obsidian-livesync/data` (checksum-verified).
  - Jellyfin, Sonarr, Sonarr Anime, Radarr, Recyclarr and the download sweeper run on Aerith with the image digests Rinoa ran. Configs were pre-copied, then a final copy ran with the services stopped.
  - Recyclarr moved too, because it reads the arr API keys from local `config.xml` files.
  - Rinoa Traefik routes to Aerith through the file provider. Prowlarr applications and Seerr servers point to `192.168.1.118`; arr indexers point to `http://192.168.1.110:9696`.
- Backups and rollback: `/mnt/titan/Backups/storage-locality-2026-11-01/` holds configs, the Plex archive, the Forgejo tar, its manifest and a `pg_dump`, and the cutover and revert scripts.
  - The originals stay in place and inactive: `/mnt/titan/docker/forgejo`, `/mnt/titan/docker/obsidian-livesync/data`, and the Jellyfin and arr configs on Rinoa.
  - Revert: `sudo bash ~/storage-locality/revert-aerith-1.sh` on Aerith, then `sudo bash ~/storage-locality/revert-rinoa-2.sh` on Rinoa. Rollback generations are pinned in `~/storage-locality/`. Prowlarr and Seerr settings from before the cutover are in `~/storage-locality/app-settings-before/` on Rinoa (mode 0600).
- 2026-11-01: Sonarr Anime and Radarr qBittorrent download clients changed from the stale `192.168.1.117` to `192.168.1.112` through their APIs (connection tests passed). The previous settings are in `~/storage-locality/app-settings-before/` on Aerith (mode 0600). The sweeper default also changed to `.112`; it takes effect at the next Aerith rebuild.
- Open: Phase 2 private network. Recurring local Forgejo/CouchDB backups to Titan. Remove the old copies after seven days (from 2026-11-08), by explicit decision only.
