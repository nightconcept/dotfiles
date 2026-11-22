#!/usr/bin/env bash
# Weekly pull of Titan's essential folders from mog to Jeanne (plan 005, Phase 2).
#
# Reads Titan on mog's local disk over SSH, never over SMB. --delete keeps the mirror
# exact; --backup-dir keeps every file Titan deleted or changed for RETAIN_DAYS days.
set -euo pipefail

src_host=${TITAN_BACKUP_HOST:-mog}
src_root=${TITAN_BACKUP_SRC:-/export/titan}
pool=${TITAN_BACKUP_POOL:-/srv/mergerfs/pool0}
dst=${TITAN_BACKUP_DST:-/mnt/jeanne/titan-backup}
retain_days=${TITAN_BACKUP_RETAIN_DAYS:-90}
folders=(Backups Personal Photography Books Music Audiobooks Comics Software data vesper)
stamp=$(date +%F)

# Never write to the root disk if Jeanne is not mounted.
mountpoint -q /mnt/jeanne || { echo "titan-backup: /mnt/jeanne is not mounted" >&2; exit 1; }

# Never mirror an empty source: an unmounted pool would make --delete wipe the backup.
ssh -o BatchMode=yes "$src_host" "mountpoint -q '$pool' && test -d '$src_root/Backups'" \
  || { echo "titan-backup: Titan's pool is not mounted on $src_host" >&2; exit 1; }

mkdir -p "$dst/.deleted"
for folder in "${folders[@]}"; do
  echo "titan-backup: $folder"
  rsync -aH --numeric-ids --delete --partial --info=stats1 \
    --backup --backup-dir="$dst/.deleted/$stamp/$folder" \
    --exclude='.Trash-*/' \
    "$src_host:$src_root/$folder/" "$dst/$folder/"
done

find "$dst/.deleted" -mindepth 1 -maxdepth 1 -type d -mtime "+$retain_days" -print -exec rm -rf {} +
echo "titan-backup: done"
