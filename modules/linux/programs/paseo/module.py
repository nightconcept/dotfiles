"""Paseo module for host configuration managed by pyinfra."""

import os

from pyinfra.operations import files, server

from modules.linux.module import HostModule


class PaseoModule(HostModule):
    """Manages Paseo daemon and agent CLI stack using Docker Compose."""

    def __init__(self, port: int = 6767):
        """Initialize directory paths and port configuration."""
        self.base_dir = "/opt/paseo"
        self.home_dir = "/opt/paseo/home"
        self.workspace_dir = "/home/danny/git"
        self.local_dir = os.path.dirname(__file__)
        self.local_compose = os.path.join(self.local_dir, "docker-compose.yml")
        self.local_dockerfile = os.path.join(self.local_dir, "Dockerfile")
        self.port = port

    def install(self):
        """Create runtime and persistent state directories."""
        for path in [
            self.base_dir,
            self.home_dir,
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
        """Deploy Docker files and environment, then start the stack."""
        files.put(
            name="Deploy Paseo docker-compose.yml",
            src=self.local_compose,
            dest=f"{self.base_dir}/docker-compose.yml",
            _sudo=True,
            user="danny",
        )

        files.put(
            name="Deploy Paseo Dockerfile",
            src=self.local_dockerfile,
            dest=f"{self.base_dir}/Dockerfile",
            _sudo=True,
            user="danny",
        )

        server.shell(
            name="Write Paseo environment file",
            commands=[
                (
                    "cat > {base_dir}/.env <<'EOF'\n"
                    "PASEO_PASSWORD=change-me\n"
                    "PASEO_HOSTNAMES=terra,terra.local.solivan.dev,localhost,127.0.0.1\n"
                    "PASEO_HOME_DIR={home_dir}\n"
                    "WORKSPACE_DIR={workspace_dir}\n"
                    "EOF"
                ).format(
                    base_dir=self.base_dir,
                    home_dir=self.home_dir,
                    workspace_dir=self.workspace_dir,
                )
            ],
            _sudo=True,
        )

        server.shell(
            name="Start Paseo stack",
            commands=[
                f"docker compose --env-file {self.base_dir}/.env "
                f"-f {self.base_dir}/docker-compose.yml up -d --build"
            ],
            _sudo=True,
        )

    def service(self):
        """Paseo container restart policy is handled by Docker Compose."""
        pass

    def remove(self):
        """Stop and remove the Paseo stack."""
        server.shell(
            name="Stop Paseo stack",
            commands=[
                f"docker compose --env-file {self.base_dir}/.env "
                f"-f {self.base_dir}/docker-compose.yml down"
            ],
            _sudo=True,
        )
