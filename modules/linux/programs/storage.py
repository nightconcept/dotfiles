"""Storage module for host configuration."""

import os
from pyinfra.operations import apt, files, server

from modules.linux.module import HostModule


class StorageModule(HostModule):
    """Manages RAID storage and mounting using local scripts."""

    def __init__(self):
        self.mount_script = "scripts/mount-terra-drives.sh"
        self.mount_path = "/mnt/terra"

    def install(self):
        """Ensure storage dependencies and directories are present."""
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
        """Execute the mount script to ensure arrays are assembled and mounted."""
        # Transfer the script and run it
        script_dest = "/tmp/mount-terra-drives.sh"
        
        files.put(
            name="Upload mount script",
            src=self.mount_script,
            dest=script_dest,
            mode="755",
            _sudo=True,
        )

        server.shell(
            name="Run mount script",
            commands=[script_dest],
            _sudo=True,
        )

    def service(self):
        """Configuration for persistent mounting if needed."""
        # The script handles mounting; for a more permanent solution, 
        # one could add fstab entries here if IDs were known.
        pass

    def remove(self):
        """Unmount the storage (does not destroy RAID)."""
        server.shell(
            name=f"Unmount {self.mount_path}",
            commands=[f"umount {self.mount_path} || true"],
            _sudo=True,
        )
