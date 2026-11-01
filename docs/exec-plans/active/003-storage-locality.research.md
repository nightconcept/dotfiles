# Storage locality research

Status: active
Last reviewed: 2026-11-01
Owner: danny

## Scope and evidence quality

This note preserves findings reported in the originating conversation for a later implementation session.
No live scans, migrations, restarts, or network changes were performed while writing it.
Measurements below came from live diagnostic commands in the originating conversation.
Raw command output is not copied into this document.
Treat the measurements as historical snapshots. Refresh them before execution.
The companion [plan](003-storage-locality.plan.md) owns sequencing and acceptance criteria.

The user explicitly keeps BookOrbit, Audiobookshelf, and LibbyRip converter on Rinoa.
Aerith's future storage capacity remains an unresolved decision, despite sufficient space for the measured initial transfer.

## Reported incident and I/O snapshots

Source for this section: originating conversation, before this planning request.

| Observation | Reported value or behavior |
|---|---|
| Forgejo repository page | HTTP 500 after 57.7 seconds |
| Forgejo preceding ten minutes | 53 server errors; 140 slow-request warnings |
| Rinoa load | Approximately 22 on four CPUs; substantial I/O stalls |
| Git processes | Blocked waiting for storage; `git pack-objects` among affected processes |
| Jellyfin | 367 MB read in ten seconds, mostly cached; active library scan and repeated probe errors |
| Rinoa to Titan SMB | Approximately 900 operations/second, mostly opens, closes, and metadata queries; only 145 KB read in ten seconds |
| Titan physical disks | Low activity during the sample |
| Forgejo workload | Repeated fetch/push for `nightconcept/porygon2`; earlier history, diff, and blame requests |
| BookOrbit | Negligible reads during the sample |
| DNS/TLS/connectivity | Fast during checks |
| Later authenticated repository API | 89 ms; this does not establish browser recovery |

These observations support storage latency as a leading hypothesis, but do not prove its exact cause.
They do not attribute every SMB operation to an individual process or client.
Jellyfin's cached process reads are not equivalent to network bytes or physical disk reads.
Many Forgejo HTTP requests were Actions polling, which does not establish heavy repository I/O.
Tunnel proxy addresses obscured originating clients.
The samples need not represent simultaneous or sustained conditions.

## Service storage snapshots

Source for sizes: originating conversation's storage analysis; totals are rounded.
Media libraries are excluded from application-state figures and remain on Titan.

| Service/state | Reported size | Placement implication |
|---|---:|---|
| Plex existing state | 39.43 GiB | Already on Aerith; metadata is a substantial continuing growth source |
| Jellyfin state | 12.27 GiB | Proposed Aerith move; metadata alone is 11.1 GiB |
| Radarr state | 2.45 GiB | Proposed Aerith move |
| Sonarr state | 1.07 GiB | Proposed Aerith move |
| Sonarr Anime state | 0.30 GiB | Proposed Aerith move |
| Proposed combined transfer | 16.09 GiB | Excludes images and future growth |
| Aerith available before transfer | 39.84 GiB | Historical guest filesystem free space |
| Aerith available after transfer | 23.75 GiB | Arithmetic estimate only; before images and growth |
| Rinoa available | Approximately 106 GiB | Historical guest filesystem free space |
| Aerith available RAM | Approximately 14 GiB | Capacity snapshot, not a sustained workload guarantee |

CouchDB data occupied about 81.5 MiB on Titan.
The retained book/audio services and future container images have no complete size inventory in this investigation.
Do not invent a capacity forecast from these missing figures.

### Forgejo detail

Source: originating conversation's measured breakdown.

| Forgejo data on Titan | Reported size |
|---|---:|
| Git repositories | 1.93 GiB |
| Generated repository archives | 1.99 GiB |
| Actions artifacts | 0.85 GiB |
| Git LFS objects | 0.44 GiB |
| Packages | 0.30 GiB |
| Attachments | 0.22 GiB |
| Other state | Small |
| Total | Approximately 5.74 GiB |

There were 108 repositories.
The largest repository directories were `metamon` (714 MiB) and `SDL3-CS` (349 MiB).
`zekrom` occupied only 724 KiB; its repository size does not explain the reported delay.
PostgreSQL already occupied local Rinoa storage: 106 MiB in its data directory, including a 38 MiB Forgejo database.

The [Forgejo module](../../../modules/nixos/services/docker/containers/forgejo/default.nix) defaults application data to `/mnt/titan/docker/forgejo` and PostgreSQL to `/var/lib/docker-containers/forgejo/db`.
Its [Compose definition](../../../modules/nixos/services/docker/containers/forgejo/docker-compose.yml) mounts the former as `/data`.
Moving the entire `/data` tree to local Rinoa storage removes this active SMB dependency without moving the service VM.
The existing `remoteDataPath` option accepts a local path; its name does not require remote storage.
The module already conditions Titan mount dependencies on that path's prefix.
Back up local application state and its database consistently to Titan after cutover.
Archive and artifact retention are future capacity controls, not permission to delete existing data during migration.

The [LiveSync module](../../../modules/nixos/services/docker/containers/obsidian-livesync/default.nix) also defaults live data to Titan.
Its local-storage change requires a fresh size measurement and an application-consistent backup procedure.

## VM and network evidence

The repository's [network reference](../../network.md) places Rinoa on Valefor and Mog, Aerith, Barrett, and Vincent on Locke.
It records Aerith on `vmbr1`, Mog on `vmbr0` and `vmbr2`, and all three bridges attached to separate physical ports.
Rinoa therefore necessarily uses an inter-host network path to Mog.

Earlier conversation checks reported Aerith learning Mog's destination MAC through a physical Ethernet port on Locke.
That supports a physical switch round trip for the observed Aerith storage path despite VM co-location.
The same checks reported two Mog NICs on the same LAN subnet with equal route metrics, with `.167` reached through the other NIC's MAC.
This is consistent with ARP/interface ambiguity; raw captures are absent from this handoff, so verify before changing NICs.
Do not infer cable topology solely from bridge names.

Proxmox documents Linux bridges as virtual switches connecting guests and optional physical interfaces.
A shared isolated bridge on Locke can keep Aerith-to-Mog packets within the host.
SMB still uses the network stack; locality removes the external physical path rather than all protocol overhead.
[Proxmox network documentation](https://github.com/proxmox/pve-docs/blob/master/pve-network.adoc)

The proposed storage network uses additional NICs and a separate subnet, with no gateway on those NICs.
Existing LAN NICs retain reverse proxy, SSH, client, and internet connectivity.
Traefik on Rinoa can reach Aerith through its LAN address while Aerith mounts Mog through its private address.
Select unused bridge/subnet/NIC identifiers during implementation; none are reserved by this note.
Barrett needs the same storage path while preserving NordVPN protection and allowed LAN access.
The existing [Linux Titan mount](../../../modules/linux/services/titan_mount.py) hardcodes Mog's LAN address and needs consideration for a per-host private endpoint.

Moving media scanners to Locke reduces cross-host storage traffic; it does not inherently reduce SMB operation counts.
Local Forgejo/CouchDB data removes their active SMB operations.
Scan scheduling, failed-probe fixes, and metadata caching can reduce remaining operations.
The kernel documents `actimeo` as an attribute cache lifetime: longer values reduce server calls but delay metadata freshness.
An earlier report identified `actimeo=1`; any longer-cache experiment needs current mount verification and workload checks.
Use separate media mounts for experiments rather than blanket database/Git changes.
[Linux CIFS documentation](https://www.kernel.org/doc/html/latest/admin-guide/cifs/usage.html)

## Aerith capacity decision

The 23.75 GiB projected remainder proves only that the measured state fits once.
It does not establish enough capacity for metadata growth, updates, container images, logs, or temporary transcoding files.
Keep database, index, and thumbnail state local rather than moving it onto SMB to conceal the capacity problem.
Before moving services, measure growth and transient storage needs, select a reserve, and decide whether Aerith remains the target.
Possible outcomes include fewer migrated services, an additional physical SSD, or deliberate reallocation of existing VM disk commitments.
No option is selected or authorized for execution by this research note.

[Locke storage](../../network.md) has a 370.82 GiB thin pool and 370 GiB of promised VM disks.
Disk sizes are Mog 25, Barrett 40, Garnet 93, Vincent 100, and Aerith 112 GiB.
The volume group has no free extents.
Guest free space is not unallocated hypervisor capacity.
The repository prohibits pool overcommit and Proxmox snapshots on this pool.
Do not grow Aerith or create another VM without a capacity decision consistent with [plan 002](002-locke-zero-overcommit.plan.md).

## Placement carried into planning

| VM | Intended disposition |
|---|---|
| Rinoa | Keep Traefik and web apps, Forgejo/PostgreSQL, CouchDB, BookOrbit, Audiobookshelf, and LibbyRip converter; make Forgejo/CouchDB active state local |
| Aerith | Keep Plex; proposed Jellyfin, Radarr, Sonarr, Sonarr Anime and one download sweeper, subject to capacity decision |
| Barrett | Keep qBittorrent and SABnzbd; add private storage path while preserving VPN behavior |
| Mog | Keep storage role; expose private SMB endpoint without relocating applications onto it |
| Vincent | Keep CI/monitoring/security roles; avoid using this VM as an unplanned media-storage workaround |

Rinoa's [host configuration](../../../hosts/nixos/rinoa/default.nix) enables the current Docker media applications.
Aerith's [host configuration](../../../hosts/nixos/aerith/default.nix) currently enables Plex and Titan mounting.
Cross-host media backends need explicit LAN ports and Traefik routes; Rinoa's Docker discovery does not discover remote containers.
Retained Rinoa book/audio workloads still traverse the physical network for Titan access, as required by the user.
