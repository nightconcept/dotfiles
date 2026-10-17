"""Pinchflat YouTube downloader stack for Terra."""

import os

from pyinfra.operations import files, server

from modules.linux.module import HostModule


class PinchflatModule(HostModule):
    """Deploy the Pinchflat Docker Compose stack."""

    def __init__(self):
        """Initialize deployment, config, and download paths."""
        self.base_dir = "/opt/pinchflat"
        self.config_dir = "/home/danny/docker/pinchflat/config"
        self.downloads_dir = "/mnt/storage/pinchflat/downloads"
        self.local_dir = os.path.dirname(__file__)
        self.local_compose = os.path.join(self.local_dir, "docker-compose.yml")

    def install(self):
        """Create persistent directories owned by the container user."""
        for directory in [self.base_dir, self.config_dir, self.downloads_dir]:
            files.directory(
                name=f"Ensure pinchflat directory {directory} exists",
                path=directory,
                present=True,
                _sudo=True,
                user="danny",
                group="danny",
            )

    def update(self):
        """Deploy the Compose file and start the container."""
        files.put(
            name="Deploy pinchflat Docker Compose file",
            src=self.local_compose,
            dest=f"{self.base_dir}/docker-compose.yml",
            _sudo=True,
            user="danny",
        )
        server.shell(
            name="Start Pinchflat",
            commands=[
                (
                    f"PINCHFLAT_CONFIG_PATH={self.config_dir} "
                    f"PINCHFLAT_DOWNLOADS_PATH={self.downloads_dir} "
                    f"docker compose -f {self.base_dir}/docker-compose.yml up -d"
                ),
            ],
            _sudo=True,
        )

    def service(self):
        """Use Docker Compose restart policies for service lifecycle."""

    def remove(self):
        """Stop the stack while preserving config and downloads."""
        server.shell(
            name="Stop pinchflat stack",
            commands=[f"docker compose -f {self.base_dir}/docker-compose.yml down"],
            _sudo=True,
        )
