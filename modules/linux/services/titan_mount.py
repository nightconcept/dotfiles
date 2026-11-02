"""Titan network mount module for host configuration."""

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
What={source}
Where=/mnt/titan
Type=cifs
Options=credentials={credentials},uid=1000,gid=100,iocharset=utf8,nofail,_netdev,x-systemd.automount,x-systemd.mount-timeout=10

[Install]
WantedBy=multi-user.target
"""

_AUTOMOUNT_UNIT = """\
[Unit]
Description=Automount Titan network share

[Automount]
Where=/mnt/titan
TimeoutIdleSec=0
DirectoryMode=0755

[Install]
WantedBy=multi-user.target
"""


class TitanMountModule(HostModule):
    """Manages the Titan CIFS network drive automount."""

    def __init__(
        self,
        source: str = "//192.168.1.167/titan",
        credentials: str = "/etc/mog-secrets",
    ):
        """Initialize Titan mount module.

        Args:
            source: CIFS share path. Hosts on the Locke storage network use
                Mog's private address.
            credentials: CIFS credentials file on the host.
        """
        self.source = source
        self.credentials = credentials

    def install(self):
        """Ensure cifs-utils is installed and mount point exists."""
        server.shell(
            name="Install cifs-utils and ensure /mnt/titan mount point exists",
            commands=[
                "if ! dpkg -s cifs-utils >/dev/null 2>&1; then "
                "apt-get update && apt-get install -y cifs-utils; fi",
                "mkdir -p /mnt/titan",
            ],
            _sudo=True,
        )

    def update(self):
        """Nothing to update — CIFS mount is static."""
        pass

    def service(self):
        """Deploy systemd mount and automount units."""
        credentials_file = host.get_fact(File, path=self.credentials, _sudo=True)
        if not credentials_file:
            server.shell(
                name="Warn when titan credentials are missing",
                commands=[
                    f"echo 'WARNING: {self.credentials} not found - skipping titan mount setup'"
                ],
            )
            return

        units = "/etc/systemd/system/mnt-titan"
        mount_unit = _MOUNT_UNIT.format(source=self.source, credentials=self.credentials)
        server.shell(
            name="Deploy Titan mount and automount units",
            commands=[
                f"cat > {units}.mount <<'UNIT_EOF'\n{mount_unit}UNIT_EOF",
                f"cat > {units}.automount <<'UNIT_EOF'\n{_AUTOMOUNT_UNIT}UNIT_EOF",
                f"chmod 644 {units}.mount {units}.automount",
            ],
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
