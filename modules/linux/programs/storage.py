"""Storage module for Terra's local filesystems."""

from pyinfra.operations import apt, files, server

from modules.linux.module import HostModule

# Filesystem UUIDs identify the arrays independently of md device names or labels.
_LOCAL_MOUNTS = (
    ("19b4b338-5216-4a18-8b97-5f4a2f61970e", "/mnt/storage"),
    ("4e809462-b3ce-44ac-a0d6-b4da00904fb7", "/mnt/jeanne"),
    ("b8fc4c1e-90de-4e14-96a2-523916652bdb", "/mnt/lancelot"),
)

_ASSEMBLE_SCRIPT = """\
set -eu
jeanne=/dev/disk/by-uuid/4e809462-b3ce-44ac-a0d6-b4da00904fb7
lancelot=/dev/disk/by-uuid/b8fc4c1e-90de-4e14-96a2-523916652bdb
if [ ! -b "$jeanne" ] || [ ! -b "$lancelot" ]; then
    # mdadm can return nonzero when there are no additional arrays to assemble.
    # The required devices below determine whether deployment can continue.
    mdadm --assemble --scan || echo 'Checking required RAID devices after assembly' >&2
    udevadm settle
fi
for device in "$jeanne" "$lancelot"; do
    if [ ! -b "$device" ]; then
        echo "ERROR: required RAID filesystem is unavailable: $device" >&2
        exit 1
    fi
done
"""


class StorageModule(HostModule):
    """Manages Terra's local storage mounts; used only by its host deployment."""

    def install(self):
        """Install RAID tools and create the mount directories."""
        apt.packages(
            name="Install mdadm for RAID management",
            packages=["mdadm"],
            update=True,
            _sudo=True,
        )

        for _, mount_point in _LOCAL_MOUNTS:
            files.directory(
                name=f"Ensure {mount_point} exists",
                path=mount_point,
                _sudo=True,
            )

    def update(self):
        """Persist UUID mounts and mount the existing filesystems."""
        server.shell(
            name="Assemble Terra's existing RAID arrays",
            commands=[_ASSEMBLE_SCRIPT],
            _sudo=True,
        )

        for uuid, mount_point in _LOCAL_MOUNTS:
            files.line(
                name=f"Persist {mount_point} mount",
                path="/etc/fstab",
                line=f"UUID={uuid} {mount_point} ext4 defaults,nofail 0 2",
                _sudo=True,
            )

        server.shell(
            name="Reload systemd mount configuration",
            commands=["systemctl daemon-reload"],
            _sudo=True,
        )

        for uuid, mount_point in _LOCAL_MOUNTS:
            server.shell(
                name=f"Mount and verify {mount_point}",
                commands=[
                    f"""set -eu
                    if ! mountpoint -q '{mount_point}'; then
                        mount '{mount_point}'
                    fi
                    test "$(findmnt -rn -M '{mount_point}' -o UUID)" = '{uuid}'
                    """
                ],
                _sudo=True,
            )

    def service(self):
        """Mount persistence is handled by fstab."""
        pass

    def remove(self):
        """Unmount the managed filesystems and remove their fstab entries."""
        for uuid, mount_point in reversed(_LOCAL_MOUNTS):
            server.mount(
                name=f"Unmount {mount_point}",
                path=mount_point,
                mounted=False,
                _sudo=True,
            )
            files.line(
                name=f"Remove {mount_point} mount from fstab",
                path="/etc/fstab",
                line=f"UUID={uuid} {mount_point} ext4 defaults,nofail 0 2",
                present=False,
                _sudo=True,
            )
