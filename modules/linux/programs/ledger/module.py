"""Paisa Ledger stack for Terra, plus the Actual Budget -> hledger sync timer."""

import io
import os

from pyinfra.operations import files, server, systemd

from modules.linux.module import HostModule

_SYNC_COMMAND = (
    "/home/danny/.nix-profile/bin/uv run --with actualpy "
    "python3 {ledger_dir}/scripts/sync_actual.py --commit --push"
)

_SYNC_SERVICE_UNIT = """\
[Unit]
Description=Regenerate hledger journal from Actual Budget
After=docker.service network-online.target
Wants=docker.service network-online.target

[Service]
Type=oneshot
User=danny
Group=danny
WorkingDirectory={ledger_dir}
Environment=PATH=/home/danny/.local/bin:/home/danny/.nix-profile/bin:/home/danny/.ghcup/bin:/usr/local/bin:/usr/bin:/bin
ExecStart={sync_command}
"""

_SYNC_TIMER_UNIT = """\
[Unit]
Description=Run the Actual Budget -> hledger sync daily

[Timer]
OnCalendar={on_calendar}
Persistent=true
Unit=ledger-sync.service

[Install]
WantedBy=timers.target
"""


class LedgerModule(HostModule):
    """Deploy the Paisa Docker Compose stack against the Ledger checkout."""

    def __init__(self, sync_on_calendar: str = "*-*-* 06:00:00"):
        """Initialize deployment and persistent-data paths."""
        self.base_dir = "/opt/ledger"
        self.paisa_data_dir = "/home/danny/docker/paisa/data"
        self.ledger_dir = "/home/danny/git/ledger"
        self.sync_on_calendar = sync_on_calendar
        self.local_dir = os.path.dirname(__file__)
        self.local_compose = os.path.join(self.local_dir, "docker-compose.yml")
        self.local_paisa_config = os.path.join(self.local_dir, "paisa.yaml")

    def install(self):
        """Create persistent directories without removing existing financial data."""
        for directory in [self.base_dir, self.paisa_data_dir]:
            files.directory(
                name=f"Ensure ledger directory {directory} exists",
                path=directory,
                present=True,
                _sudo=True,
                user="danny",
                group="danny",
            )

    def update(self):
        """Deploy stack assets, seed only missing defaults, and start containers."""
        files.put(
            name="Deploy ledger Docker Compose file",
            src=self.local_compose,
            dest=f"{self.base_dir}/docker-compose.yml",
            _sudo=True,
            user="danny",
        )
        files.put(
            name="Deploy Paisa configuration template",
            src=self.local_paisa_config,
            dest=f"{self.base_dir}/paisa.yaml.template",
            _sudo=True,
            user="danny",
        )
        server.shell(
            name="Require Ledger checkout and seed missing Paisa configuration",
            commands=[
                f'test -f "{self.ledger_dir}/ledger/main.journal"',
                (
                    f'test -e "{self.paisa_data_dir}/paisa.yaml" || '
                    f"install -o danny -g danny -m 0640 "
                    f'"{self.base_dir}/paisa.yaml.template" '
                    f'"{self.paisa_data_dir}/paisa.yaml"'
                ),
                (
                    f"PAISA_DATA_PATH={self.paisa_data_dir} "
                    f"LEDGER_PATH={self.ledger_dir} "
                    f"docker compose -f {self.base_dir}/docker-compose.yml up -d --wait"
                ),
            ],
            _sudo=True,
        )

        files.put(
            name="Deploy ledger-sync.service unit",
            src=io.StringIO(
                _SYNC_SERVICE_UNIT.format(
                    ledger_dir=self.ledger_dir,
                    sync_command=_SYNC_COMMAND.format(ledger_dir=self.ledger_dir),
                )
            ),
            dest="/etc/systemd/system/ledger-sync.service",
            mode="644",
            _sudo=True,
        )
        files.put(
            name="Deploy ledger-sync.timer unit",
            src=io.StringIO(_SYNC_TIMER_UNIT.format(on_calendar=self.sync_on_calendar)),
            dest="/etc/systemd/system/ledger-sync.timer",
            mode="644",
            _sudo=True,
        )

    def service(self):
        """Use Docker Compose restart policies for Paisa; enable the sync timer."""
        systemd.service(
            name="Enable ledger-sync.timer",
            service="ledger-sync.timer",
            running=True,
            enabled=True,
            daemon_reload=True,
            _sudo=True,
        )

    def remove(self):
        """Stop the stack and sync timer while preserving persistent data directories."""
        systemd.service(
            name="Disable ledger-sync.timer",
            service="ledger-sync.timer",
            running=False,
            enabled=False,
            _sudo=True,
        )
        server.shell(
            name="Stop ledger stack",
            commands=[f"docker compose -f {self.base_dir}/docker-compose.yml down"],
            _sudo=True,
        )
