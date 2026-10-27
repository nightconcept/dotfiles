"""Alert through Gotify when Hermes's model emits a known exfiltration indicator."""

import io
import os

from pyinfra.operations import files, systemd

from modules.linux.module import HostModule

_SCRIPT_SRC = os.path.join(os.path.dirname(__file__), "hermes_ioc_alert.py")
_SCRIPT_PATH = "/usr/local/sbin/hermes-ioc-alert"
_CONFIG_DIR = "/etc/hermes-ioc-alert"
_TOKEN_PATH = f"{_CONFIG_DIR}/gotify.token"
_SERVICE_PATH = "/etc/systemd/system/hermes-ioc-alert.service"
_TIMER_PATH = "/etc/systemd/system/hermes-ioc-alert.timer"

# Root-owned so the agent, which runs as the Hermes user, cannot edit or stop it.
_SERVICE = """[Unit]
Description=Alert on known exfiltration indicators in Hermes model output
After=network-online.target

[Service]
Type=oneshot
StateDirectory=hermes-ioc-alert
ExecStart={script} --db {db} --uid {uid} --gotify-url {gotify_url} \\
    --token-file {token} --state /var/lib/hermes-ioc-alert/state.json
"""

_TIMER = """[Unit]
Description=Scan Hermes model output every minute

[Timer]
OnBootSec=2min
OnUnitActiveSec=1min

[Install]
WantedBy=timers.target
"""


class HermesIocAlertModule(HostModule):
    """Scan Hermes's tool calls and journal every minute and push hits to Gotify."""

    def __init__(self, user="danny", uid=1000, gotify_url="http://192.168.1.185:8070"):
        """Configure the scanner.

        Args:
            user: Account that runs hermes-gateway.
            uid: That account's UID, for filtering its journal.
            gotify_url: Gotify server that receives the alerts.
        """
        self.db = f"/home/{user}/.hermes/state.db"
        self.uid = uid
        self.gotify_url = gotify_url

    def install(self):
        """Create the root-only directory for the Gotify token."""
        files.directory(
            name=f"Ensure {_CONFIG_DIR} exists",
            path=_CONFIG_DIR,
            mode="700",
            user="root",
            group="root",
            _sudo=True,
        )

    def update(self):
        """Install the scanner script."""
        files.put(
            name="Install the Hermes IOC scanner",
            src=_SCRIPT_SRC,
            dest=_SCRIPT_PATH,
            mode="755",
            user="root",
            group="root",
            _sudo=True,
        )

    def service(self):
        """Run the scanner every minute."""
        unit = _SERVICE.format(
            script=_SCRIPT_PATH,
            db=self.db,
            uid=self.uid,
            gotify_url=self.gotify_url,
            token=_TOKEN_PATH,
        )
        files.put(
            name="Deploy hermes-ioc-alert.service unit",
            src=io.StringIO(unit),
            dest=_SERVICE_PATH,
            mode="644",
            _sudo=True,
        )
        files.put(
            name="Deploy hermes-ioc-alert.timer unit",
            src=io.StringIO(_TIMER),
            dest=_TIMER_PATH,
            mode="644",
            _sudo=True,
        )
        systemd.service(
            name="Enable hermes-ioc-alert.timer",
            service="hermes-ioc-alert.timer",
            running=True,
            enabled=True,
            daemon_reload=True,
            _sudo=True,
        )

    def remove(self):
        """Disable the timer and remove the scanner. The token is kept."""
        systemd.service(
            name="Disable hermes-ioc-alert.timer",
            service="hermes-ioc-alert.timer",
            running=False,
            enabled=False,
            _sudo=True,
        )
        for path in (_TIMER_PATH, _SERVICE_PATH, _SCRIPT_PATH):
            files.file(name=f"Remove {path}", path=path, present=False, _sudo=True)
