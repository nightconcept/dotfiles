"""Titan network mount module for host configuration."""

from io import StringIO

from pyinfra import host
from pyinfra.facts.files import File
from pyinfra.operations import files, server, systemd

from ..module import HostModule

_MOUNT_UNIT = """\
[Unit]
Description=Mount Titan network share
After=network-online.target
Wants=network-online.target

[Mount]
What=//192.168.1.167/titan
Where=/mnt/titan
Type=cifs
Options=credentials=/etc/mog-secrets,uid=1000,gid=100,iocharset=utf8,nofail,_netdev,x-systemd.automount,x-systemd.mount-timeout=10

[Install]
WantedBy=multi-user.target
"""

_AUTOMOUNT_UNIT = """\
[Unit]
Description=Automount Titan network share

[Automount]
Where=/mnt/titan
TimeoutIdleSec=60
DirectoryMode=0755

[Install]
WantedBy=multi-user.target
"""


class TitanMountModule(HostModule):
    """Manages the Titan CIFS network drive automount."""

    def install(self):
        """Ensure cifs-utils is installed and mount point exists."""
        server.shell(
            name="Install cifs-utils (if missing)",
            commands=[
                "if ! dpkg -s cifs-utils >/dev/null 2>&1; then "
                "apt-get update && apt-get install -y cifs-utils; fi"
            ],
            _sudo=True,
        )

        files.directory(
            name="Ensure /mnt/titan mount point exists",
            path="/mnt/titan",
            present=True,
            _sudo=True,
        )

    def update(self):
        """Nothing to update — CIFS mount is static."""
        pass

    def service(self):
        """Deploy systemd mount and automount units."""
        credentials_file = host.get_fact(File, path="/etc/mog-secrets", _sudo=True)
        if not credentials_file:
            server.shell(
                name="Warn when titan credentials are missing",
                commands=[
                    "echo 'WARNING: /etc/mog-secrets not found - skipping titan mount setup'"
                ],
            )
            return

        files.put(
            name="Deploy mnt-titan.mount unit",
            src=StringIO(_MOUNT_UNIT),
            dest="/etc/systemd/system/mnt-titan.mount",
            mode="644",
            _sudo=True,
        )

        files.put(
            name="Deploy mnt-titan.automount unit",
            src=StringIO(_AUTOMOUNT_UNIT),
            dest="/etc/systemd/system/mnt-titan.automount",
            mode="644",
            _sudo=True,
        )

        systemd.service(
            name="Enable mnt-titan.automount",
            service="mnt-titan.automount",
            running=True,
            enabled=True,
            daemon_reload=True,
            _sudo=True,
        )

    def remove(self):
        """Disable and remove the titan mount units."""
        systemd.service(
            name="Disable mnt-titan.automount",
            service="mnt-titan.automount",
            running=False,
            enabled=False,
            _sudo=True,
        )
        files.file(
            name="Remove mnt-titan.mount unit",
            path="/etc/systemd/system/mnt-titan.mount",
            present=False,
            _sudo=True,
        )
        files.file(
            name="Remove mnt-titan.automount unit",
            path="/etc/systemd/system/mnt-titan.automount",
            present=False,
            _sudo=True,
        )
