"""Tailscale module for host configuration."""

from pyinfra.operations import server, systemd

from ..module import HostModule


class TailscaleModule(HostModule):
    """Manages Tailscale installation and tailnet connection."""

    def __init__(self, login_server: str | None = None):
        """Initialize Tailscale module.

        Args:
            login_server: Coordination server URL (e.g. a self-hosted Headscale
                instance). Defaults to Tailscale's own SaaS control server.
        """
        self.login_server = login_server

    def install(self):
        """Install Tailscale using the official install script if not present."""
        server.shell(
            name="Install Tailscale (if missing)",
            commands=[
                "if ! command -v tailscale >/dev/null 2>&1; then "
                "curl -fsSL https://tailscale.com/install.sh | sh; fi"
            ],
            _sudo=True,
        )

        systemd.service(
            name="Enable tailscaled",
            service="tailscaled",
            running=True,
            enabled=True,
            _sudo=True,
        )

    def update(self):
        """Tailscale auto-updates through its apt repo — nothing to do."""
        pass

    def service(self):
        """Join the tailnet using an auth key, if not already connected."""
        login_server_flag = f"--login-server {self.login_server} " if self.login_server else ""
        server.shell(
            name="Connect to tailnet",
            commands=[
                f"""
                set -eu

                if ! tailscale status >/dev/null 2>&1 || tailscale status 2>&1 | grep -q "Logged out"; then
                    KEY_FILE=/root/.tailscale-authkey
                    if [ -f "$KEY_FILE" ]; then
                        tailscale up {login_server_flag}--auth-key "$(cat $KEY_FILE)"
                    else
                        echo "WARNING: /root/.tailscale-authkey not found — skipping tailscale up"
                        exit 0
                    fi
                fi
                """,
            ],
            _sudo=True,
        )

    def remove(self):
        """Logout and uninstall Tailscale."""
        server.shell(
            name="Logout and purge Tailscale",
            commands=["tailscale logout || true", "apt-get purge -y tailscale || true"],
            _sudo=True,
        )
