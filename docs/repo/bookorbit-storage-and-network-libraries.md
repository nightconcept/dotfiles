# BookOrbit storage and network libraries

## Recommendation

BookOrbit does **not** need to run on Terra. It can run on any Docker host
that can mount or otherwise reach Titan. Keep its application data and
PostgreSQL data on durable local storage on that host, and mount the Titan
library into the app. The official installation describes the install folder
as the home for Compose and its default persistent data, while allowing
`BOOKS_HOST_PATH` to point at an existing library elsewhere. It lists about
50 MB for the app in addition to book-file storage. [Installation guide](https://bookorbit.app/installation)

For the Rinoa deployment, `/home/danny/docker/bookorbit/data/app` and
`/home/danny/docker/bookorbit/data/postgres` are correctly local to Rinoa. The
Titan CIFS share is a valid library source at `/mnt/titan`, exposed in the container as
`/books`; its libraries should be `/books/Books` and `/books/Audiobooks`.
The official Compose file uses the same separation: a book-directory bind
mount plus persistent `/data` and PostgreSQL volumes. [Official Compose file](https://github.com/bookorbit/bookorbit/blob/main/docker-compose.yml)

Use **Watch folders: off** and configure a scheduled auto-scan for each
Titan-backed library. BookOrbit says native events from NFS, SMB, CIFS, S3FS,
and similar network mounts are not reliable. It also notes that inode-based
move tracking can be unavailable on network mounts; a scan re-discovers a
moved file, and background reconciliation resolves stale missing states.
[Adding books](https://bookorbit.app/adding-books)

Mount Titan read-only unless BookOrbit is deliberately the writer for these
folders. Reading/scanning needs only `PUID:PGID` read access. Write access is
needed for browser uploads, Book Dock finalization, metadata writes, and
renames. Automatic metadata writes and renames default to off, but the manual
**Write to File & Rename** action still writes and can move a whole
Folder-as-Book directory. BookOrbit specifically recommends a read-only mount
for a tree another catalog server manages. [Installation guide](https://bookorbit.app/installation)
[Creating a library](https://bookorbit.app/creating-a-library)
[Book details](https://bookorbit.app/book-details)

## Comparison with the existing Calibre stack on Terra

| Concern | Calibre / Calibre-Web | BookOrbit |
| --- | --- | --- |
| Application state | Local Terra bind mounts: `/opt/books-stack/calibre:/config` and `/opt/books-stack/calibre-web:/config`. | Local Rinoa bind mounts: `/home/danny/docker/bookorbit/data/app:/data` and `/home/danny/docker/bookorbit/data/postgres:/var/lib/postgresql/data`. |
| Canonical library mount | Both Calibre containers use `/mnt/calibre-library` (`/library` or `/books`). | The app uses `/mnt/titan:/books`; individual libraries are selected below it. |
| Titan access | Calibre alone also mounts `/mnt/titan/Books` and `/mnt/titan/Books-Unorganized`, both writable by default. | The entire Titan share is mounted writable by default in the current Compose file. |
| Network-mount behavior | The Compose file has no Calibre-specific CIFS health gate. | BookOrbit officially supports a network mount, but requires watcher-off plus scheduled/manual scans for dependable discovery. |
| Failure behavior | If Titan is absent, Calibre's local library remains available; its Titan-mounted input folders are unavailable. | If Titan is absent or unreadable, scans can find no books and writes can fail with permission errors. The Rinoa service requires the Titan mount and waits for it before starting. |

The Calibre comparison is from the current repository Compose and module
configuration: [Calibre Compose](../../modules/linux/programs/books/docker-compose.yml),
[BookOrbit Compose](../../modules/nixos/services/docker/containers/bookorbit/docker-compose.yml),
and [Rinoa host definition](../../hosts/nixos/rinoa/default.nix).

## Operational choice

Rinoa is the selected BookOrbit host because it has the durable Titan mount and
the local Traefik endpoint. Keep BookOrbit's `/data` and PostgreSQL volumes on
Rinoa-local storage; do not put PostgreSQL on the CIFS share.
