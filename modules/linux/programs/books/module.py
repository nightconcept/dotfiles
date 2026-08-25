"""Books modules for host configuration."""

import os
import shlex

from pyinfra.operations import files, server

from modules.linux.module import HostModule


class BooksModule(HostModule):
    """Manages Calibre and Calibre-Web using a static Docker Compose file."""

    def __init__(self):
        """Initialize the Calibre and Calibre-Web deployment paths."""
        self.base_dir = "/opt/books-stack"
        self.local_compose = os.path.join(os.path.dirname(__file__), "docker-compose.yml")

    def install(self):
        """Create necessary directories and cleanup old ones."""
        server.shell(
            name="Prepare Books stack directories",
            commands=[
                "rm -rf /mnt/terra/data/books",
                f'mkdir -p "{self.base_dir}/calibre" "{self.base_dir}/calibre-web" && '
                f'chown -R danny:danny "{self.base_dir}"',
            ],
            _sudo=True,
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


class BookOrbitModule(HostModule):
    """Deploy BookOrbit alongside the existing Calibre and Calibre-Web stack."""

    def __init__(
        self,
        enabled: bool = False,
        library_path: str = "/mnt/calibre-library",
    ):
        """Initialize BookOrbit paths and its optional deployment setting."""
        self.enabled = enabled
        self.library_path = library_path
        self.base_dir = "/opt/bookorbit"
        self.local_dir = os.path.dirname(__file__)
        self.local_compose = os.path.join(self.local_dir, "bookorbit-compose.yml")
        self.local_env_template = os.path.join(self.local_dir, "bookorbit.env.example")

    def install(self):
        """Create BookOrbit's persistent application and database directories."""
        for directory in [
            self.base_dir,
            f"{self.base_dir}/data",
            f"{self.base_dir}/data/app",
            f"{self.base_dir}/data/postgres",
        ]:
            files.directory(
                name=f"Ensure BookOrbit directory {directory} exists",
                path=directory,
                present=True,
                _sudo=True,
                user="danny",
                group="danny",
            )

    def update(self):
        """Deploy BookOrbit assets, seed its environment, and start the stack."""
        files.put(
            name="Deploy BookOrbit Docker Compose file",
            src=self.local_compose,
            dest=f"{self.base_dir}/docker-compose.yml",
            _sudo=True,
            user="danny",
        )
        files.put(
            name="Deploy BookOrbit environment template",
            src=self.local_env_template,
            dest=f"{self.base_dir}/.env.template",
            _sudo=True,
            user="danny",
        )
        server.shell(
            name="Seed BookOrbit environment and start stack",
            commands=[
                (
                    f'test -f "{self.base_dir}/.env" || '
                    f'(install -o danny -g danny -m 0600 "{self.base_dir}/.env.template" '
                    f'"{self.base_dir}/.env" && '
                    f'token=$(openssl rand -hex 16) && '
                    f'sed -i "s/CHANGE_THIS_SETUP_BOOTSTRAP_TOKEN/$token/" '
                    f'"{self.base_dir}/.env")'
                ),
                (
                    f"BOOKS_HOST_PATH={shlex.quote(self.library_path)} "
                    f"docker compose -f {self.base_dir}/docker-compose.yml up -d --wait"
                ),
            ],
            _sudo=True,
        )

    def service(self):
        """Use Docker Compose restart policies for the BookOrbit lifecycle."""

    def remove(self):
        """Stop BookOrbit while preserving its data and environment file."""
        server.shell(
            name="Stop BookOrbit stack",
            commands=[f"docker compose -f {self.base_dir}/docker-compose.yml down"],
            _sudo=True,
        )
