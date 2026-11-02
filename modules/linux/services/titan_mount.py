"""Titan network mount module for host configuration."""

from pyinfra import host
from pyinfra.facts.server import Home
from pyinfra.operations import files, server, systemd

from ..module import HostModule
from ..packages import install_packages

_MOUNT_UNIT = """\
[Unit]
Description=Mount Titan network share
After=network-online.target
Wants=network-online.target

[Mount]
What={source}
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
TimeoutIdleSec=0
DirectoryMode=0755

[Install]
WantedBy=multi-user.target
"""

_CREDENTIALS = "/etc/mog-secrets"
_SOPS_FILE = "git/dotfiles/modules/nixos/security/sops/common.yaml"
_SOPS_KEY = "network/titan_credentials"

# Decrypt into a root-only temp file so plaintext never reaches argv or pyinfra
# output. Keep an existing credentials file when decryption is unavailable.
_SYNC_CREDENTIALS = """\
set -u
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
if SOPS_AGE_KEY_FILE={home}/.config/sops/age/keys.txt \\
    {home}/.nix-profile/bin/sops --decrypt --extract '["network"]["titan_credentials"]' \\
    {home}/{sops_file} > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
  if ! cmp -s "$tmp" {credentials}; then
    install -m 600 -o root -g root "$tmp" {credentials}
    echo "Updated {credentials} from SOPS ({sops_key})"
  fi
elif [ -f {credentials} ]; then
  echo "WARNING: SOPS decryption failed; keeping existing {credentials}"
else
  echo "ERROR: cannot decrypt {sops_key} and {credentials} is missing." >&2
  echo "Install the age key at {home}/.config/sops/age/keys.txt (run bootstrap.sh)." >&2
  exit 1
fi
"""


class TitanMountModule(HostModule):
    """Manages the Titan CIFS network drive automount."""

    def __init__(self, source: str = "//192.168.1.167/titan"):
        """Initialize Titan mount module.

        Args:
            source: CIFS share path. Hosts on the Locke storage network use
                Mog's private address.
        """
        self.source = source

    def install(self):
        """Ensure cifs-utils is installed and mount point exists."""
        install_packages(name="Install cifs-utils", debian=["cifs-utils"])
        files.directory(
            name="Ensure /mnt/titan mount point exists",
            path="/mnt/titan",
            _sudo=True,
        )

    def update(self):
        """Nothing to update — CIFS mount is static."""
        pass

    def service(self):
        """Sync credentials from SOPS, then deploy systemd mount and automount units."""
        server.shell(
            name="Sync Titan credentials from SOPS",
            commands=[
                _SYNC_CREDENTIALS.format(
                    home=host.get_fact(Home),
                    sops_file=_SOPS_FILE,
                    sops_key=_SOPS_KEY,
                    credentials=_CREDENTIALS,
                )
            ],
            _sudo=True,
        )

        units = "/etc/systemd/system/mnt-titan"
        mount_unit = _MOUNT_UNIT.format(source=self.source)
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
