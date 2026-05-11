"""NordVPN module for host configuration."""

from pyinfra.operations import files, server, systemd

from ..module import HostModule


class NordVPNModule(HostModule):
    """Manages NordVPN installation and configuration on Debian."""

    def __init__(self, user: str = "danny"):
        """Initialize NordVPN module."""
        self.user = user

    def install(self):
        """Install NordVPN using the official install script if not present."""
        server.shell(
            name="Install NordVPN (if missing)",
            commands=[
                "if ! command -v nordvpn >/dev/null 2>&1; then "
                "sh <(curl -sSf https://downloads.nordcdn.com/apps/linux/install.sh) --non-interactive; fi"
            ],
        )

        server.shell(
            name=f"Add {self.user} to nordvpn group",
            commands=[f"usermod -aG nordvpn {self.user}"],
            _sudo=True,
        )

        systemd.service(
            name="Enable nordvpnd",
            service="nordvpnd",
            running=True,
            enabled=True,
            _sudo=True,
        )

    def update(self):
        """NordVPN auto-updates through its apt repo — nothing to do."""
        pass

    def service(self):
        """Configure NordVPN settings from token file."""
        server.shell(
            name="Configure NordVPN settings",
            commands=[
                """
                set -eu

                # Wait for daemon to be ready
                for i in $(seq 1 15); do
                    nordvpn status >/dev/null 2>&1 && break
                    echo "Waiting for NordVPN daemon... ($i/15)"
                    sleep 2
                done

                # Login with token if not already logged in
                if ! nordvpn account >/dev/null 2>&1; then
                    TOKEN_FILE=/root/.nordvpn-token
                    if [ -f "$TOKEN_FILE" ]; then
                        nordvpn login --token "$(cat $TOKEN_FILE)"
                    else
                        echo "WARNING: /root/.nordvpn-token not found — skipping login"
                        exit 0
                    fi
                fi

                # Apply settings (idempotent)
                nordvpn set technology NordLynx
                nordvpn set lan-discovery enable
                nordvpn set dns 103.86.96.100 103.86.99.100
                nordvpn set autoconnect on

                # Connect if not already connected
                if ! nordvpn status | grep -q "Status: Connected"; then
                    nordvpn connect p2p
                fi
                """,
            ],
            _sudo=True,
        )

    def remove(self):
        """Uninstall NordVPN."""
        server.shell(
            name="Purge NordVPN",
            commands=["apt-get purge -y nordvpn || true"],
            _sudo=True,
        )
