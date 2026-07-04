"""Storage module for host configuration."""

from pyinfra.operations import apt, files, server

from modules.linux.module import HostModule

_MOUNT_SCRIPT = """
set -euo pipefail
mdadm --assemble --scan || true
sleep 2
md_devices=$(grep "^md" /proc/mdstat | cut -d" " -f1)
for dev in $md_devices; do
    dev_path="/dev/$dev"
    label=$(lsblk -no LABEL "$dev_path" | head -n1 || echo "raid-$dev")
    mount_point="/mnt/$label"
    mkdir -p "$mount_point"
    if mountpoint -q "$mount_point"; then
        echo "$dev_path already mounted at $mount_point"
    elif mount "$dev_path" "$mount_point" 2>/dev/null; then
        echo "Mounted $dev_path at $mount_point"
    elif command -v pvs &>/dev/null && pvs "$dev_path" &>/dev/null; then
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


class StorageModule(HostModule):
    """Manages RAID storage and mounting."""

    def install(self):
        apt.packages(
            name="Install mdadm for RAID management",
            packages=["mdadm"],
            update=True,
            _sudo=True,
        )

        for mount_point in ["/mnt/terra", "/mnt/jeanne"]:
            files.directory(
                name=f"Ensure {mount_point} exists",
                path=mount_point,
                present=True,
                _sudo=True,
            )

    def update(self):
        server.shell(
            name="Assemble and mount RAID arrays",
            commands=[_MOUNT_SCRIPT],
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
