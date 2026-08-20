"""Storage module for host configuration."""

from pyinfra.operations import apt, server

from modules.linux.module import HostModule

_MOUNT_SCRIPT = """
set -eu
mdadm --assemble --scan || true
sleep 2
md_devices=$(grep "^md" /proc/mdstat | cut -d" " -f1)
for dev in $md_devices; do
    dev_path="/dev/$dev"
    label=$(lsblk -dno LABEL "$dev_path" | head -n1)
    if [ -z "$label" ]; then
        array_name=$(
            mdadm --detail --export "$dev_path" 2>/dev/null |
                sed -n 's/^MD_NAME=//p' |
                head -n1
        )
        label=${array_name%%:*}
    fi
    if ! printf '%s' "$label" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]*$'; then
        echo "ERROR: refusing to mount $dev_path without a safe filesystem label or array name" >&2
        continue
    fi
    mount_point="/mnt/$label"
    mkdir -p "$mount_point"
    if mountpoint -q "$mount_point"; then
        echo "$dev_path already mounted at $mount_point"
    elif mount "$dev_path" "$mount_point" 2>/dev/null; then
        echo "Mounted $dev_path at $mount_point"
    elif command -v pvs >/dev/null 2>&1 && pvs "$dev_path" >/dev/null 2>&1; then
        vgscan && vgchange -ay
        vg_name=$(pvs "$dev_path" --noheadings -o vg_name | tr -d ' ')
        for lv in $(lvs "$vg_name" --noheadings -o lv_name | tr -d ' '); do
            lv_path="/dev/$vg_name/$lv"
            lv_mount="/mnt/$vg_name-$lv"
            mkdir -p "$lv_mount"
            mount "$lv_path" "$lv_mount" && echo "Mounted $lv_path at $lv_mount"
        done
    else
        echo "ERROR: failed to mount $dev_path" >&2
    fi
done
"""

_STORAGE_UUID = "19b4b338-5216-4a18-8b97-5f4a2f61970e"
_STORAGE_MOUNT_POINT = "/mnt/storage"
_STORAGE_FSTAB_LINE = (
    f"UUID={_STORAGE_UUID} {_STORAGE_MOUNT_POINT} ext4 defaults,nofail 0 2"
)


class StorageModule(HostModule):
    """Manages Terra's local storage mounts."""

    def install(self):
        apt.packages(
            name="Install mdadm for RAID management",
            packages=["mdadm"],
            update=True,
            _sudo=True,
        )

        server.shell(
            name="Ensure /mnt/terra, /mnt/jeanne and /mnt/storage exist",
            commands=["mkdir -p /mnt/terra /mnt/jeanne " + _STORAGE_MOUNT_POINT],
            _sudo=True,
        )

    def update(self):
        server.shell(
            name="Mount storage NVMe and assemble RAID arrays",
            commands=[
                f'''set -eu
                fstab_line='{_STORAGE_FSTAB_LINE}'
                grep -Fqx "$fstab_line" /etc/fstab || echo "$fstab_line" >> /etc/fstab
                if ! mountpoint -q "{_STORAGE_MOUNT_POINT}"; then
                    mount "{_STORAGE_MOUNT_POINT}"
                fi''',
                _MOUNT_SCRIPT,
            ],
            _sudo=True,
        )

    def service(self):
        pass

    def remove(self):
        server.shell(
            name="Unmount terra storage",
            commands=["umount /mnt/terra || true"],
            _sudo=True,
        )
