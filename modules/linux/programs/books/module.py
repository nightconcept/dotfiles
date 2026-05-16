"""Books module for host configuration (Calibre & Calibre-Web)."""

import os
from pyinfra.operations import files, server

from modules.linux.module import HostModule


class BooksModule(HostModule):
    """Manages Calibre and Calibre-Web using a static Docker Compose file."""

    def __init__(self):
        self.base_dir = "/opt/books-stack"
        self.local_compose = os.path.join(os.path.dirname(__file__), "docker-compose.yml")

    def install(self):
        """Create necessary directories and cleanup old ones."""
        # Cleanup old incorrect path if it exists
        server.shell(
            name="Cleanup old incorrect books path",
            commands=["rm -rf /mnt/terra/data/books"],
            _sudo=True,
        )

        for path in [
            self.base_dir,
            f"{self.base_dir}/calibre",
            f"{self.base_dir}/calibre-web",
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
        """Deploy docker-compose.yml and start containers."""
        files.put(
            name="Deploy Books docker-compose.yml",
            src=self.local_compose,
            dest=f"{self.base_dir}/docker-compose.yml",
            _sudo=True,
            user="danny",
        )

        server.shell(
            name="Start Books stack",
            commands=[f"docker compose -f {self.base_dir}/docker-compose.yml up -d"],
            _sudo=True,
        )

    def service(self):
        """Containers are managed by Docker."""
        pass

    def remove(self):
        """Stop and remove Books stack."""
        server.shell(
            name="Stop Books stack",
            commands=[f"docker compose -f {self.base_dir}/docker-compose.yml down"],
            _sudo=True,
        )
