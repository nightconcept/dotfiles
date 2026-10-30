"""SABnzbd deployment for Barrett's VPN and Titan storage."""

import io
from pathlib import Path

from pyinfra.operations import files, server, systemd

from ...module import HostModule

SERVICE_UNIT = """\
[Unit]
Description=SABnzbd Usenet downloader
Wants=network-online.target
Requires=nordvpnd.service
After=network-online.target nordvpnd.service
RequiresMountsFor=/mnt/titan
StartLimitIntervalSec=0

[Service]
Type=simple
User=danny
Group=users
UMask=0077
StateDirectory=sabnzbd
StateDirectoryMode=0700
ExecStartPre=/usr/local/libexec/sabnzbd-vpn-ready
ExecStartPre=/usr/bin/mountpoint -q /mnt/titan
ExecStartPre=+/usr/bin/python3 /usr/local/libexec/sabnzbd-bootstrap.py
ExecStart=/usr/bin/sabnzbdplus --config-file /var/lib/sabnzbd/sabnzbd.ini \\
    --server 192.168.1.112:8080 --browser 0
Restart=on-failure
RestartSec=15s
PrivateTmp=true

[Install]
WantedBy=multi-user.target
"""

VPN_READY = """\
#!/bin/sh
set -eu
export LC_ALL=C
status=$(nordvpn status)
printf '%s\\n' "$status" | grep -q 'Status: Connected'
settings=$(nordvpn settings)
printf '%s\\n' "$settings" | grep -Fxq 'Kill Switch: enabled'
ip link show nordlynx >/dev/null
"""


class SABnzbdModule(HostModule):
    """Install SABnzbd with persistent local settings and shared download storage."""

    def install(self):
        """Enable Debian archive components and install the packaged downloader."""
        secret_source = Path("hosts/linux/barrett/secrets/sabnzbd.yaml")
        if not secret_source.is_file():
            raise RuntimeError(
                "Create hosts/linux/barrett/secrets/sabnzbd.yaml with SOPS before deployment"
            )
        server.shell(
            name="Install SABnzbd from Debian contrib",
            commands=[
                """\
set -eu
. /etc/os-release
test "$ID" = debian
cat > /etc/apt/sources.list.d/sabnzbd.list <<EOF
deb https://deb.debian.org/debian ${VERSION_CODENAME} contrib non-free
deb https://security.debian.org/debian-security ${VERSION_CODENAME}-security contrib non-free
EOF
apt-get update
apt-get install -y sabnzbdplus unrar
"""
            ],
            _sudo=True,
        )
        files.directory(
            name="Create SABnzbd helper directory",
            path="/usr/local/libexec",
            mode="755",
            _sudo=True,
        )
        files.directory(
            name="Create encrypted SABnzbd credential directory",
            path="/etc/sabnzbd",
            mode="700",
            _sudo=True,
        )
        secret = files.put(
            name="Deploy SOPS-encrypted SABnzbd credentials",
            src=str(secret_source),
            dest="/etc/sabnzbd/secrets.yaml",
            mode="600",
            _sudo=True,
        )
        self._credentials_changed = secret.did_change
        helper = files.put(
            name="Install SABnzbd configuration helper",
            src=str(Path(__file__).with_name("bootstrap.py")),
            dest="/usr/local/libexec/sabnzbd-bootstrap.py",
            mode="644",
            _sudo=True,
        )
        guard = files.put(
            name="Install SABnzbd VPN startup check",
            src=io.StringIO(VPN_READY),
            dest="/usr/local/libexec/sabnzbd-vpn-ready",
            mode="755",
            _sudo=True,
        )
        self._helpers_changed = helper.did_change or guard.did_change

    def update(self):
        """Preserve application settings; the startup helper applies SOPS credentials."""

    def service(self):
        """Install and enable the service using the Debian package's unit name."""
        unit = files.put(
            name="Deploy sabnzbdplus.service",
            src=io.StringIO(SERVICE_UNIT),
            dest="/etc/systemd/system/sabnzbdplus.service",
            mode="644",
            _sudo=True,
        )
        systemd.service(
            name="Enable and start SABnzbd",
            service="sabnzbdplus",
            running=True,
            enabled=True,
            restarted=unit.did_change or self._credentials_changed or self._helpers_changed,
            daemon_reload=True,
            _sudo=True,
        )

    def remove(self):
        """Stop SABnzbd, retaining settings and downloaded files."""
        systemd.service(
            name="Stop SABnzbd",
            service="sabnzbdplus",
            running=False,
            enabled=False,
            _sudo=True,
        )
