"""Actual Budget and Paisa stack for Terra."""

import os

from pyinfra.operations import files, server

from modules.linux.module import HostModule


class BudgetModule(HostModule):
    """Deploy the Actual Budget and Paisa Docker Compose stack."""

    def __init__(self):
        """Initialize deployment and persistent-data paths."""
        self.base_dir = "/opt/budget"
        self.actual_data_dir = "/home/danny/docker/actual/data"
        self.paisa_data_dir = "/home/danny/docker/paisa/data"
        self.ledger_dir = "/home/danny/git/ledger"
        self.local_dir = os.path.dirname(__file__)
        self.local_compose = os.path.join(self.local_dir, "docker-compose.yml")
        self.local_paisa_config = os.path.join(self.local_dir, "paisa.yaml")

    def install(self):
        """Create persistent directories without removing existing financial data."""
        for directory in [
            self.base_dir,
            self.actual_data_dir,
            self.paisa_data_dir,
        ]:
            files.directory(
                name=f"Ensure budget directory {directory} exists",
                path=directory,
                present=True,
                _sudo=True,
                user="danny",
                group="danny",
            )

    def update(self):
        """Deploy stack assets, seed only missing defaults, and start containers."""
        files.put(
            name="Deploy budget Docker Compose file",
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
                    f"ACTUAL_DATA_PATH={self.actual_data_dir} "
                    f"PAISA_DATA_PATH={self.paisa_data_dir} "
                    f"LEDGER_PATH={self.ledger_dir} "
                    f"docker compose -f {self.base_dir}/docker-compose.yml up -d --wait"
                ),
            ],
            _sudo=True,
        )

    def service(self):
        """Use Docker Compose restart policies for service lifecycle."""

    def remove(self):
        """Stop the stack while preserving its persistent data directories."""
        server.shell(
            name="Stop budget stack",
            commands=[f"docker compose -f {self.base_dir}/docker-compose.yml down"],
            _sudo=True,
        )
