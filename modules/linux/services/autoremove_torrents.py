"""Autoremove-torrents module for host configuration."""

import io

from pyinfra.operations import files, server, systemd

from ..module import HostModule

_SERVICE_UNIT = """\
[Unit]
Description=Remove torrents automatically
After=qbittorrent.service
Wants=qbittorrent.service

[Service]
Type=oneshot
User=root
ExecStart=/usr/local/bin/autoremove-torrents --conf=/etc/autoremove-torrents/config.yml --log=/var/log/autoremove-torrents
"""

_TIMER_UNIT = """\
[Unit]
Description=Run autoremove-torrents every {interval_minutes} minutes

[Timer]
OnBootSec={interval_minutes}min
OnUnitActiveSec={interval_minutes}min
Unit=autoremove-torrents.service

[Install]
WantedBy=timers.target
"""

_CONFIG_TEMPLATE = """\
qbittorrent_task:
  client: qbittorrent
  host: http://127.0.0.1:{webui_port}
  username: {username}
  password: "{password}"
  strategies:
    minimal_seed_strategy:
      remove: '{remove_rule}'
      delete_data: true
"""


class AutoremoveTorrentsModule(HostModule):
    """Manages autoremove-torrents installation and seeding-limit configuration."""

    def __init__(
        self,
        user: str = "danny",
        webui_port: int = 8112,
        username: str = "danny",
        password_file: str = "/root/.qbittorrent-password",
        interval_minutes: int = 5,
        remove_rule: str = "seeding_time > 600",
    ):
        """Initialize autoremove-torrents module."""
        self.user = user
        self.webui_port = webui_port
        self.username = username
        self.password_file = password_file
        self.interval_minutes = interval_minutes
        self.remove_rule = remove_rule

    def install(self):
        """Install autoremove-torrents via pip and create log directory."""
        server.shell(
            name="Install autoremove-torrents (if missing)",
            commands=[
                "if ! command -v autoremove-torrents >/dev/null 2>&1; then "
                "pip3 install --break-system-packages autoremove-torrents; fi"
            ],
            _sudo=True,
        )

        for path, owner in [
            ("/etc/autoremove-torrents", "root"),
            (f"/var/log/autoremove-torrents", self.user),
        ]:
            files.directory(
                name=f"Ensure {path} exists",
                path=path,
                present=True,
                user=owner,
                _sudo=True,
            )

    def update(self):
        """Write config from password file."""
        server.shell(
            name="Write autoremove-torrents config from password file",
            commands=[
                f"""
                set -eu
                if [ ! -f "{self.password_file}" ]; then
                    echo "WARNING: {self.password_file} not found — config not written"
                    exit 0
                fi
                PASSWORD=$(cat "{self.password_file}")
                cat > /etc/autoremove-torrents/config.yml << CONF
qbittorrent_task:
  client: qbittorrent
  host: http://127.0.0.1:{self.webui_port}
  username: {self.username}
  password: "$PASSWORD"
  strategies:
    minimal_seed_strategy:
      remove: '{self.remove_rule}'
      delete_data: true
CONF
                chmod 600 /etc/autoremove-torrents/config.yml
                echo "autoremove-torrents config written"
                """
            ],
            _sudo=True,
        )

    def service(self):
        """Deploy systemd service and timer units."""
        files.put(
            name="Deploy autoremove-torrents.service unit",
            src=io.StringIO(_SERVICE_UNIT),
            dest="/etc/systemd/system/autoremove-torrents.service",
            mode="644",
            _sudo=True,
        )

        timer = _TIMER_UNIT.format(interval_minutes=self.interval_minutes)
        files.put(
            name="Deploy autoremove-torrents.timer unit",
            src=io.StringIO(timer),
            dest="/etc/systemd/system/autoremove-torrents.timer",
            mode="644",
            _sudo=True,
        )

        systemd.service(
            name="Enable autoremove-torrents.timer",
            service="autoremove-torrents.timer",
            running=True,
            enabled=True,
            daemon_reload=True,
            _sudo=True,
        )

    def remove(self):
        """Disable timer and uninstall autoremove-torrents."""
        systemd.service(
            name="Disable autoremove-torrents.timer",
            service="autoremove-torrents.timer",
            running=False,
            enabled=False,
            _sudo=True,
        )
        server.shell(
            name="Uninstall autoremove-torrents",
            commands=["pip3 uninstall -y autoremove-torrents || true"],
            _sudo=True,
        )
