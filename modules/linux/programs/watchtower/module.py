"""Watchtower module for host configuration (automatic Docker image updates)."""

import os

from pyinfra.operations import files, server

from modules.linux.module import HostModule


class WatchtowerModule(HostModule):
    """Manages Watchtower using a static Docker Compose file."""

    def __init__(self):
        self.base_dir = "/opt/watchtower"
        self.local_compose = os.path.join(os.path.dirname(__file__), "docker-compose.yml")

    def install(self):
        """Create the base directory."""
        files.directory(
            name=f"Ensure directory {self.base_dir} exists",
            path=self.base_dir,
            present=True,
            _sudo=True,
            user="danny",
            group="danny",
        )

    def update(self):
        """Deploy docker-compose.yml and start Watchtower."""
        files.put(
            name="Deploy Watchtower docker-compose.yml",
            src=self.local_compose,
            dest=f"{self.base_dir}/docker-compose.yml",
            _sudo=True,
            user="danny",
        )

        server.shell(
            name="Start Watchtower stack",
            commands=[f"docker compose -f {self.base_dir}/docker-compose.yml up -d"],
            _sudo=True,
        )

    def service(self):
        """Container restart policy is handled by Docker Compose."""
        pass

    def remove(self):
        """Stop and remove Watchtower."""
        server.shell(
            name="Stop Watchtower stack",
            commands=[f"docker compose -f {self.base_dir}/docker-compose.yml down"],
            _sudo=True,
        )
