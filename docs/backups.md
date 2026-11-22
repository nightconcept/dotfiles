# Backups and terra's storage arrays

This page covers the code. Where data is meant to live, and why, is in the home repo:
`~/git/home/docs/storage.md`. The plan and its history are in
`~/git/home/docs/plans/titan-backup-and-layout.md`.

## Terra's arrays

`modules/linux/programs/storage.py` mounts both RAID5 arrays on terra through fstab, by
UUID:

| Mount | Array | Role (set in home) |
|---|---|---|
| `/mnt/jeanne` | md0, 15 TB | Backup of Titan's essential folders |
| `/mnt/lancelot` | md1, 7.3 TB | Cold storage for Vesper data, AI data, and archived caches |

## titan-backup

Module: `modules/linux/programs/titan_backup/` (`TitanBackupModule`), deployed by
`hosts/linux/terra/main.py`.

What it installs:

- `/usr/local/bin/titan-backup`, from `titan-backup.sh`.
- `titan-backup.service`: a oneshot run as `danny` at idle I/O priority. It needs
  `/mnt/jeanne` mounted.
- `titan-backup.timer`: Sundays at 05:00, `Persistent=true`. That is after mog's 03:30
  SnapRAID sync and outside rotom's 23:00 to 04:00 GPU window.
- `titan-backup-alert.service`: posts to Gotify on failure. It needs a token in
  `/etc/titan-backup/gotify.token` (root only) and exits quietly without one.

What the script does:

1. Stops if `/mnt/jeanne` is not mounted, so it never fills the root disk.
2. Checks over SSH that mog's pool (`/srv/mergerfs/pool0`) is mounted and
   `/export/titan/Backups` exists. An empty source with `--delete` would wipe the backup.
3. For each folder (`Backups Personal Photography Books Music Audiobooks Comics
   Software data vesper`), runs `rsync -aH --delete` from `mog:/export/titan/<folder>/`
   to `/mnt/jeanne/titan-backup/<folder>/`. It reads Titan on mog's local disk, never
   over SMB.
4. Moves changed and deleted files to `/mnt/jeanne/titan-backup/.deleted/<date>/`, and
   removes dated folders there older than 90 days.

The folder list is the backup policy in `~/git/home/docs/storage.md`. When Titan's
layout changes (for example `vesper` and `data` moving to `Projects/`), change the list
and the home page in the same change.

Settings come from environment variables with defaults: `TITAN_BACKUP_HOST` (mog),
`TITAN_BACKUP_SRC`, `TITAN_BACKUP_POOL`, `TITAN_BACKUP_DST`, and
`TITAN_BACKUP_RETAIN_DAYS` (90).

Deploy with `just terra`. Run it by hand with `sudo systemctl start titan-backup`, and
read the log with `journalctl -u titan-backup`.
