"""Weekly backup of Titan's essential folders from mog to Terra's Jeanne array."""

import io
import os

from pyinfra.operations import files, systemd

from modules.linux.module import HostModule

_SCRIPT_DEST = "/usr/local/bin/titan-backup"
_TOKEN_DIR = "/etc/titan-backup"
_TOKEN_PATH = f"{_TOKEN_DIR}/gotify.token"

_SERVICE_UNIT = """\
[Unit]
Description=Back up Titan's essential folders from mog to Jeanne
After=network-online.target mnt-jeanne.mount
Wants=network-online.target
RequiresMountsFor=/mnt/jeanne
OnFailure=titan-backup-alert.service

[Service]
Type=oneshot
User={user}
Group={user}
Nice=10
IOSchedulingClass=idle
ExecStart={script}
"""

_TIMER_UNIT = """\
[Unit]
Description=Run the Titan backup weekly

[Timer]
OnCalendar={on_calendar}
Persistent=true
Unit=titan-backup.service

[Install]
WantedBy=timers.target
"""

# The token stays in a root-only file and goes in a header, so it never reaches logs.
_ALERT_UNIT = """\
[Unit]
Description=Alert through Gotify when the Titan backup fails

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'test -r {token} || exit 0; \
curl --fail --silent --show-error -o /dev/null -H "X-Gotify-Key: $(cat {token})" \
-F title="titan-backup failed on terra" \
-F message="Run: journalctl -u titan-backup" -F priority=8 {gotify_url}/message'
"""


class TitanBackupModule(HostModule):
    """Install the titan-backup script, its weekly timer, and a failure alert."""

    def __init__(
        self,
        user="danny",
        on_calendar="Sun *-*-* 05:00:00",
        gotify_url="http://192.168.1.185:8070",
    ):
        """Set the run user, schedule, and Gotify server.

        Args:
            user: Account that owns the SSH key for mog and writes to Jeanne.
            on_calendar: systemd OnCalendar expression. Sunday 05:00 runs after mog's
                03:30 SnapRAID sync and outside rotom's 23:00-04:00 GPU window.
            gotify_url: Gotify server that receives failure alerts.
        """
        self.user = user
        self.on_calendar = on_calendar
        self.gotify_url = gotify_url
        self.local_script = os.path.join(os.path.dirname(__file__), "titan-backup.sh")

    def install(self):
        """Install the script and the root-only directory for the Gotify token."""
        files.put(
            name="Install the titan-backup script",
            src=self.local_script,
            dest=_SCRIPT_DEST,
            mode="755",
            _sudo=True,
        )
        files.directory(
            name="Ensure the titan-backup token directory exists",
            path=_TOKEN_DIR,
            mode="700",
            _sudo=True,
        )

    def update(self):
        """Nothing to update; install() replaces the script."""

    def service(self):
        """Install the units and enable the weekly timer."""
        units = {
            "titan-backup.service": _SERVICE_UNIT.format(user=self.user, script=_SCRIPT_DEST),
            "titan-backup.timer": _TIMER_UNIT.format(on_calendar=self.on_calendar),
            "titan-backup-alert.service": _ALERT_UNIT.format(
                token=_TOKEN_PATH, gotify_url=self.gotify_url
            ),
        }
        for name, content in units.items():
            files.put(
                name=f"Install {name}",
                src=io.StringIO(content),
                dest=f"/etc/systemd/system/{name}",
                mode="644",
                _sudo=True,
            )
        systemd.daemon_reload(name="Reload systemd for titan-backup", _sudo=True)
        systemd.service(
            name="Enable the titan-backup timer",
            service="titan-backup.timer",
            running=True,
            enabled=True,
            _sudo=True,
        )

    def remove(self):
        """Disable the timer and remove the units and script. Keeps the backup data."""
        systemd.service(
            name="Disable the titan-backup timer",
            service="titan-backup.timer",
            running=False,
            enabled=False,
            _sudo=True,
        )
        for path in (
            "/etc/systemd/system/titan-backup.service",
            "/etc/systemd/system/titan-backup.timer",
            "/etc/systemd/system/titan-backup-alert.service",
            _SCRIPT_DEST,
        ):
            files.file(name=f"Remove {path}", path=path, present=False, _sudo=True)
