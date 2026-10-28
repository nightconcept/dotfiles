# Execution Plan: Zero thin-pool overcommit on Locke, more space for Garnet

**ID:** 002
**Created:** 2026-10-28
**Status:** done 2026-10-28 (mog 25G, barrett 40G, Locke swap 2G, pool 370.82G, garnet 93G; 370G promised). Open: delete rollback images in `/var/lib/vz/dump` after 2026-10-29; install the Gotify token for `locke-pool-alert`.
**Issue/Ref:** User request to give Garnet more disk without overcommitting Locke's `local-lvm` thin pool.

## Goal

Make the sum of VM virtual disk sizes on Locke's thin pool `pve/data` ≤ the pool's physical size, and grow Garnet's root filesystem. Locke's own root (`pve/root`, `local` storage, 94 GiB) is NOT shrunk. Vincent and Aerith disks are NOT touched. Garnet gets no dedicated jobs volume; its root filesystem grows.

## Measured state (2026-10-28, read-only)

All sizes GiB (Proxmox and LVM `g` units are GiB).

Locke: `pve-manager/9.2.21`, kernel `7.0.14-25-pve`, LVM `2.03.31`. Single NVMe (Micron 2400, 476.9G) is the only PV of VG `pve` (475.94 GiB, 16 GiB free). 125 GiB RAM, 56 GiB used.

| LV | Size | Notes |
|---|---|---|
| `pve/root` | 96 | ext4, `local` storage, 29 GiB used, 62 GiB free |
| `pve/swap` | 8 | fstab by path `/dev/pve/swap`; `RESUME=none`; no zram; 0 B in use |
| `pve/data` | 348.82 | thin pool, data 55.04 %, meta 2.40 %, tmeta 3.56, pmspare 3.56, `discards passdown` |

`parted` is not installed on Locke; `sfdisk`, `e2fsck`, `resize2fs`, `losetup`, `blkdiscard`, `zstd` are. No Proxmox snapshots exist.

| VMID | VM | Disk | Virtual | Guest use | Layout (512 B sectors) |
|---|---|---|---|---|---|
| 100 | mog (OMV, Debian 12) | `scsi7` `vm-100-disk-1` | 80 | 3.9 | DOS `0x11d732b4`. p1 83 bootable start 2048 size 165769216 (ext4 `/`, UUID `6db5ef6c-…`); p2 type `5` start 165773310; p5 82 start 165773312 size 1996800, swap UUID `e06326cb-c0c4-4399-9767-0fd8c35b1cda`. Six 8 TB passthrough HDDs `scsi1–6` (never touched). |
| 102 | barrett (Debian 13) | `scsi0` `vm-102-disk-0` | 50 | 21 | DOS `0x5de4a4ec`. p1 83 bootable start 2048 size 99420160; p2 type **`f`** start 99424254; p5 82 start 99424256 size 5431296, swap UUID `f3a6bdc7-38f5-461e-99b2-fe875adbf43d`. The running barrett is Debian, not `hosts/nixos/barrett`. |
| 103 | garnet (Ubuntu 24.04) | `scsi0` `vm-103-disk-0` | 80 | 28 | GPT; `sda1` bios_grub, `sda2` `/boot`, `sda3` (last) LVM PV → `ubuntu-vg/ubuntu-lv`. Root fs repaired by fsck today; second fsck clean. |
| 104 | vincent | | 100 | 43 | untouched |
| 105 | aerith | | 112 | 64 | untouched |

Verified by review: GRUB finds root by fs UUID (`search --fs-uuid`, `root=UUID=`), never by partition size; fstab and `RESUME=` use UUIDs on mog and barrett; sfdisk keeps MBR boot code unless `--wipe always`; DOS labels do not write sectors 1–2047; OMV's GRUB install device is `by-id/…drive-scsi7`; barrett's VPN kill switch is off and LAN discovery is on.

Promised today: 422 GiB on 348.82 GiB (73 GiB over).

## Target

| | Now | After |
|---|---|---|
| `pve/swap` | 8 | 2 |
| `pve/data` | 348.82 | 370.82 (+16 VG free, +6 from swap) |
| mog / barrett / vincent / aerith / garnet | 80 / 50 / 100 / 112 / 80 | **25 / 40** / 100 / 112 / **93** |
| **Promised** | 422 | **370 ≤ 370.82** |

## Phase 0 — Preconditions (no downtime)

1. Gates, else STOP: mog used ≤ 15 GiB, barrett used ≤ 28 GiB, Locke `local` free ≥ 40 GiB.
2. On Locke: `mkdir -p /root/shrink && cp /etc/pve/qemu-server/10{0,2,3}.conf /root/shrink/`, and copy `/root/shrink` to Titan.
3. Write `/root/shrink/mog-sfdisk-after.txt` and `/root/shrink/barrett-sfdisk-after.txt` (below) and diff them against `sfdisk -d` output.

### mog-sfdisk-after.txt (25 GiB = 52428800 sectors)

```
label: dos
label-id: 0x11d732b4
device: /dev/pve/vm-100-disk-1
unit: sectors
sector-size: 512

/dev/pve/vm-100-disk-1p1 : start=        2048, size=    48232448, type=83, bootable
/dev/pve/vm-100-disk-1p2 : start=    48234496, size=     4194304, type=5
/dev/pve/vm-100-disk-1p5 : start=    48236544, size=     4192256, type=82
```

### barrett-sfdisk-after.txt (40 GiB = 83886080 sectors)

```
label: dos
label-id: 0x5de4a4ec
device: /dev/pve/vm-102-disk-0
unit: sectors
sector-size: 512

/dev/pve/vm-102-disk-0p1 : start=        2048, size=    78641152, type=83, bootable
/dev/pve/vm-102-disk-0p2 : start=    78643200, size=     5242880, type=f
/dev/pve/vm-102-disk-0p5 : start=    78645248, size=     5240832, type=82
```

Sector math verified by review: mog p1 ends 48234495, p5 ends 52428799 (= 25 GiB − 1); barrett p1 ends 78643199, p5 ends 83886079 (= 40 GiB − 1); all 1 MiB aligned; p1 exceeds `FS_TMP` by ~1 GiB (mog) and ~2.5 GiB (barrett).

### Pause Titan consumers (mog window only)

Titan is CIFS (soft by default, per mount.cifs(8)): live on rinoa, terra, garnet; autofs on barrett and aerith. Verify container names with `docker ps` first.

- rinoa: `sudo systemctl stop download-sweeper.timer`; `docker stop forgejo obsidian-livesync sonarr sonarr-anime radarr jellyfin audiobookshelf bookorbit libbyrip-converter` (forgejo and obsidian-livesync keep data under `/mnt/titan/docker/`)
- terra: `docker stop calibre` (pinchflat uses local `/mnt/storage`, not Titan)
- aerith: `sudo systemctl stop plex` (with "Empty trash automatically", a scan while the share is gone can drop library items — https://support.plex.tv/articles/200289326-emptying-library-trash/)
- barrett: `sudo systemctl stop qbittorrent`
- garnet: do not reboot during the window (its fstab Titan line has no `nofail`/`_netdev`)

Resume in reverse after mog verifies; then trigger library rescans.

## Phases 1–2 — Shrink script (mog, then barrett)

Run on Locke as root, one VM at a time. The script stops at the first failure and never starts the VM.

```bash
#!/usr/bin/env bash
set -euo pipefail
# mog:     VM=100 DISK=vm-100-disk-1 NAME=mog     NEW=25 FS_TMP_G=22 SWAP_UUID=e06326cb-c0c4-4399-9767-0fd8c35b1cda
# barrett: VM=102 DISK=vm-102-disk-0 NAME=barrett NEW=40 FS_TMP_G=35 SWAP_UUID=f3a6bdc7-38f5-461e-99b2-fe875adbf43d
: "${VM:?}" "${DISK:?}" "${NAME:?}" "${NEW:?}" "${FS_TMP_G:?}" "${SWAP_UUID:?}"
LV=/dev/pve/$DISK D=/root/shrink IMG=/var/lib/vz/dump/$NAME-pre-shrink.img.zst
fsck_fix() { local rc=0; e2fsck -f -y "$1" || rc=$?; [ "$rc" -le 1 ] || { echo "e2fsck rc=$rc: STOP"; exit 1; }; }
fsck_clean() { e2fsck -f -n "$1"; }   # any non-zero exit aborts

# 1. Stop VM, record state
qm shutdown "$VM" --timeout 300
[ "$(qm status "$VM")" = "status: stopped" ]
sfdisk -d "$LV" > "$D/$NAME-sfdisk-before.txt"
dd if="$LV" bs=1M count=1 of="$D/$NAME-head.bin" status=none

# 2. Rollback image, then hash disk and image separately
rm -f "$IMG"
dd if="$LV" bs=4M status=progress | zstd -T0 -3 -q -o "$IMG"
zstd -tq "$IMG"
sha256sum < "$LV" | cut -d' ' -f1 > "$D/$NAME.sha256"
[ "$(zstdcat "$IMG" | sha256sum | cut -d' ' -f1)" = "$(cat "$D/$NAME.sha256")" ]

# 3. Shrink filesystem below the new partition size
LOOP=$(losetup -fP --show "$LV")
fsck_fix "${LOOP}p1"
MIN_BLK=$(resize2fs -P "${LOOP}p1" 2>/dev/null | awk '{print $NF}')
[ $((MIN_BLK * 4096)) -lt $((FS_TMP_G * 1024**3 * 85 / 100)) ] || { echo "fs too full for $FS_TMP_G G: STOP"; exit 1; }
resize2fs "${LOOP}p1" "${FS_TMP_G}G"
fsck_clean "${LOOP}p1"

# 4. New partition table; boot code and post-MBR gap must be unchanged
sfdisk --wipe never --wipe-partitions never --no-reread --no-tell-kernel "$LOOP" < "$D/$NAME-sfdisk-after.txt"
dd if="$LV" bs=1M count=1 of="$D/$NAME-head-after.bin" status=none
cmp -n 440 "$D/$NAME-head.bin" "$D/$NAME-head-after.bin"
cmp -i 512 -n $((2047 * 512)) "$D/$NAME-head.bin" "$D/$NAME-head-after.bin"
losetup -d "$LOOP"
LOOP=$(losetup -fP --show "$LV")
lsblk "$LOOP"
mkswap -U "$SWAP_UUID" "${LOOP}p5"
fsck_clean "${LOOP}p1"
losetup -d "$LOOP"

# 5. Free the tail in the pool, then reduce the LV
blkdiscard -f -o $((NEW * 1024**3)) "$LV"   # -f: util-linux 2.41 refuses on a TTY when a signature exists
lvreduce --fs ignore -f -L "${NEW}G" "pve/$DISK"
qm rescan --vmid "$VM"
qm config "$VM" | grep "$DISK" | grep -q "size=${NEW}G"

# 6. Grow the filesystem to fill partition 1
LOOP=$(losetup -fP --show "$LV")
fsck_fix "${LOOP}p1"
resize2fs "${LOOP}p1"
fsck_clean "${LOOP}p1"
losetup -d "$LOOP"
lvs pve/data pve/"$DISK"
echo "OK: start with qm start $VM and verify"
```

Then `qm start <VM>` by hand and verify.

- **mog** (~20 min down, Titan offline): SSH; `df /` ≈ 23 GiB; `swapon --show`; `systemctl is-active smbd nginx openmediavault-engined`; six `/srv/dev-disk-by-uuid-*` mounts; `/mnt/titan` lists on rinoa, aerith, barrett, garnet, terra; `sudo fstrim -av`.
- **barrett** (~15 min down): SSH; `df /` ≈ 37 GiB; swap active; VPN connected; qBittorrent `:8112`; Uptime Kuma Barrett checks green; `sudo fstrim -av`.

## Phase 3 — Locke pool (live, after 1–2 succeed)

```sh
free -g; swapon --show                       # swap used must be ~0
swapoff /dev/pve/swap
lvreduce --fs ignore -f -L 2G pve/swap
mkswap /dev/pve/swap && swapon -a && swapon --show
lvextend -l +100%FREE pve/data
lvs pve; pvesm status                        # data ≈ 370.82 GiB
```

After this the VG has 0 GiB free. Thin pool repair still works (pmspare 3.56 GiB exists, lvmthin(7) "Spare Metadata LV"); metadata is 2.4 % used. Growing pool metadata later needs space freed elsewhere first.

## Phase 4 — Garnet 80 → 93 GiB (live; user runs sudo)

```sh
# Locke
qm resize 103 scsi0 93G
# Garnet (user):
ssh -t garnet "lsblk /dev/sda; sudo growpart /dev/sda 3 && sudo pvresize /dev/sda3 && sudo lvextend -r -l +100%FREE ubuntu-vg/ubuntu-lv"
```

If `lsblk` still shows 80G: `echo 1 | sudo tee /sys/class/block/sda/device/rescan`. Verify `df -h /` ≈ 90 GiB.

## Phase 5 — Close-out

- Confirm promised ≤ pool: sum of local-lvm disk sizes in `qm config` vs `lvs pve/data`.
- Delete rollback images after each VM has run cleanly for 24 h.
- Before relying on vzdump for mog: set `backup=0` on its passthrough disks `scsi1–6` (repeat each existing `qm config 100` disk spec with `,backup=0` via `qm set 100 --scsiN …`), otherwise vzdump reads ~48 TB (Proxmox VE admin guide, disk `backup=` option).
- Add Gotify alert for `pve/data` data or metadata > 90 %.
- Update `docs/network.md` (garnet running; disk sizes; Locke rules below).

## Rules after completion

- No Proxmox snapshots on `local-lvm`; use `vzdump` to `local`.
- Any new disk or growth needs an equal shrink first. Pool margin is 0.82 GiB; VG free is 0.

## Contingencies

- **C1 VM will not shut down within 300 s:** script aborts. Inspect via Proxmox console; avoid `qm stop`. If forced, the script's `e2fsck -f -y` runs before any resize.
- **C2 `e2fsck` rc > 1, `resize2fs -P` gate fails, or `resize2fs` errors:** script aborts before the partition table changes. Disk is unchanged except fsck repairs. `losetup -D` if a loop remains; start the VM; report.
- **C3 Failure after the partition write, or VM does not boot:**
  ```sh
  qm stop <VM>; losetup -D
  lvextend -L <OLD>G pve/<DISK>          # 80 for mog, 50 for barrett; skip if lvs already shows OLD
  blkdiscard -f /dev/pve/<DISK>
  zstdcat /var/lib/vz/dump/<NAME>-pre-shrink.img.zst | dd of=/dev/pve/<DISK> bs=4M conv=sparse,fsync status=progress
  [ "$(sha256sum < /dev/pve/<DISK> | cut -d' ' -f1)" = "$(cat /root/shrink/<NAME>.sha256)" ]
  qm rescan --vmid <VM>; qm start <VM>
  ```
  `blkdiscard` first so `conv=sparse` leaves zeros, not stale blocks, and the restore does not allocate the full disk in the pool.
- **C4 Partition table wrong, LV not yet reduced:** `sfdisk --wipe never --no-reread --no-tell-kernel "$LV" < $D/$NAME-sfdisk-before.txt`, then re-attach the loop, `e2fsck -f -y ${LOOP}p1 && resize2fs ${LOOP}p1` (fs is at `FS_TMP`), `mkswap -U $SWAP_UUID ${LOOP}p5`, detach; otherwise C3.
- **C5 Titan consumers:** paused in Phase 0; if one was missed and marked media missing, restore from its own trash or rescan after mog returns.
- **C6 Pool space during imaging:** images go to `local` (ext4 on `pve/root`), not the pool.
- **C7 Locke host:** nothing here touches Locke boot, root fs, or network.
