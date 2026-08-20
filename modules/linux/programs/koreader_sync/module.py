"""KOReader progress-sync server module for host configuration."""

import os

from pyinfra.operations import files, server

from modules.linux.module import HostModule


class KoreaderSyncModule(HostModule):
    """Manages the koreader/kosync progress-sync server using a static Docker Compose file."""

    def __init__(self):
        self.base_dir = "/opt/kosync"
        self.local_compose = os.path.join(os.path.dirname(__file__), "docker-compose.yml")

    def install(self):
        """Create necessary directories."""
        for path in [
            self.base_dir,
            f"{self.base_dir}/logs/app",
            f"{self.base_dir}/logs/redis",
            f"{self.base_dir}/data/redis",
        ]:
            files.directory(
                name=f"Ensure directory {path} exists",
                path=path,
                present=True,
                _sudo=True,
                user="danny",
                group="danny",
            )

    def update(self):
        """Deploy docker-compose.yml and start the container."""
        files.put(
            name="Deploy kosync docker-compose.yml",
            src=self.local_compose,
            dest=f"{self.base_dir}/docker-compose.yml",
            _sudo=True,
            user="danny",
        )

        server.shell(
            name="Start kosync stack",
            commands=[f"docker compose -f {self.base_dir}/docker-compose.yml up -d"],
            _sudo=True,
        )

    def service(self):
        """Container is managed by Docker."""
        pass

    def remove(self):
        """Stop and remove the kosync stack."""
        server.shell(
            name="Stop kosync stack",
            commands=[f"docker compose -f {self.base_dir}/docker-compose.yml down"],
            _sudo=True,
        )
