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
        server.shell(
            name="Prepare Paseo stack directories",
            commands=[
                f'mkdir -p "{self.base_dir}" "{self.home_dir}" && '
                f'chown -R danny:danny "{self.base_dir}"',
            ],
            _sudo=True,
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
            name="Write Paseo environment file and start the stack",
            commands=[
                (
                    "python3 - <<'PY'\n"
                    "import os\n"
                    "import secrets\n"
                    "from pathlib import Path\n"
                    "os.umask(0o077)\n"
                    "path = Path('{base_dir}/.env')\n"
                    "values = dict(line.split('=', 1) for line in "
                    "(path.read_text().splitlines() if path.exists() else []) "
                    "if '=' in line and not line.startswith('#'))\n"
                    "if values.get('PASEO_PASSWORD', '') in ('', 'change-me'):\n"
                    "    values['PASEO_PASSWORD'] = secrets.token_urlsafe(32)\n"
                    "values.setdefault('PASEO_HOSTNAMES', "
                    "'terra,terra.local.solivan.dev,localhost,127.0.0.1')\n"
                    "values.setdefault('PASEO_HOME_DIR', '{home_dir}')\n"
                    "values.setdefault('WORKSPACE_DIR', '{workspace_dir}')\n"
                    "path.touch(mode=0o600, exist_ok=True)\n"
                    "path.chmod(0o600)\n"
                    "path.write_text(''.join(key + '=' + value + '\\n' "
                    "for key, value in values.items()))\n"
                    "PY"
                ).format(
                    base_dir=self.base_dir,
                    home_dir=self.home_dir,
                    workspace_dir=self.workspace_dir,
                ),
                f"docker compose --env-file {self.base_dir}/.env "
                f"-f {self.base_dir}/docker-compose.yml up -d --build",
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
