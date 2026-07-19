"""LibbyRip converter module for Linux hosts managed by pyinfra."""

import os

from pyinfra.operations import files, server

from modules.linux.module import HostModule


class LibbyRipConverterModule(HostModule):
    """Builds and runs the LibbyRip web converter."""

    def __init__(self, app_port: int = 8086):
        self.base_dir = "/opt/libbyrip-converter"
        self.repo_dir = "/home/danny/git/LibbyRip"
        self.local_compose = os.path.join(os.path.dirname(__file__), "docker-compose.yml")
        self.app_port = app_port

    def install(self):
        """Create runtime and persistent state directories."""
        for path in [
            self.base_dir,
            f"{self.base_dir}/data",
        ]:
            files.directory(
                name=f"Ensure directory {path} exists",
                path=path,
                present=True,
                _sudo=True,
                user="danny",
                group="danny",
            )

        server.shell(
            name="Ensure Titan library paths exist on the live CIFS mount",
            commands=[
                "systemctl start mnt-titan.mount",
                "findmnt -T /mnt/titan -n -o FSTYPE | grep -Fx cifs",
                "mkdir -p /mnt/titan/transfer/upload_audiobooks",
                "mkdir -p /mnt/titan/Audiobooks",
            ],
            _sudo=True,
        )

    def update(self):
        """Deploy compose and environment files, then start the stack."""
        files.put(
            name="Deploy LibbyRip converter docker-compose.yml",
            src=self.local_compose,
            dest=f"{self.base_dir}/docker-compose.yml",
            _sudo=True,
            user="danny",
        )

        server.shell(
            name="Write LibbyRip converter environment file",
            commands=[
                (
                    "cat > {base_dir}/.env <<'EOF'\n"
                    "LIBBYRIP_REPO={repo_dir}\n"
                    "DATA_DIR={base_dir}/data\n"
                    "UPLOAD_DIR=/mnt/titan/transfer/upload_audiobooks\n"
                    "OUTPUT_DIR=/mnt/titan/Audiobooks\n"
                    "APP_PORT={app_port}\n"
                    "EOF"
                ).format(
                    base_dir=self.base_dir,
                    repo_dir=self.repo_dir,
                    app_port=self.app_port,
                )
            ],
            _sudo=True,
        )

        server.shell(
            name="Require Titan CIFS mount before starting LibbyRip converter",
            commands=[
                "systemctl start mnt-titan.mount",
                "findmnt -T /mnt/titan/transfer/upload_audiobooks -n -o FSTYPE | grep -Fx cifs",
                "findmnt -T /mnt/titan/Audiobooks -n -o FSTYPE | grep -Fx cifs",
            ],
            _sudo=True,
        )

        server.shell(
            name="Start LibbyRip converter stack",
            commands=[f"docker compose --env-file {self.base_dir}/.env -f {self.base_dir}/docker-compose.yml up -d --build"],
            _sudo=True,
        )

    def service(self):
        """Converter is managed by Docker Compose."""
        pass

    def remove(self):
        """Stop and remove the converter stack."""
        server.shell(
            name="Stop LibbyRip converter stack",
            commands=[f"docker compose --env-file {self.base_dir}/.env -f {self.base_dir}/docker-compose.yml down"],
            _sudo=True,
        )
