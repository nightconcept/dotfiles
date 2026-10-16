"""Manage Cloud's persistent Windows VM and Forgejo runner provisioning."""

from pathlib import Path

from pyinfra.operations import files, server

from modules.linux.module import HostModule


class WindowsRunnerModule(HostModule):
    """Deploy a KVM Windows guest through Docker Compose."""

    def __init__(self):
        """Define persistent and provisioning paths."""
        self.source = Path(__file__).parent
        self.base = "/opt/cloud-windows-runner"

    def install(self):
        """Prepare protected storage and first-install credentials."""
        server.shell(
            name="Check Windows virtualization prerequisites",
            commands="test -c /dev/kvm && test -c /dev/net/tun",
            _sudo=True,
        )
        for directory in (
            self.base,
            f"{self.base}/provision",
            f"{self.base}/build",
            "/var/lib/cloud-windows-runner",
        ):
            files.directory(path=directory, mode="700", _sudo=True)
        files.file(
            name="Prepare Forgejo connection file without replacing it",
            path=f"{self.base}/provision/connection.yml",
            mode="600",
            _sudo=True,
        )
        server.shell(
            name="Generate Windows administrator password once",
            commands=(
                f"if [ ! -s {self.base}/.env ]; then "
                f"umask 077; printf 'WINDOWS_PASSWORD=Aa1!' > {self.base}/.env && "
                f"od -An -N24 -tx1 /dev/urandom | tr -d ' \\n' >> {self.base}/.env && "
                f"printf '\\n' >> {self.base}/.env; fi"
            ),
            _sudo=True,
        )

    def update(self):
        """Stage provisioning files and compile the pinned Windows executable."""
        for filename in ("install.bat", "bootstrap.ps1", "run.ps1", "config.yml"):
            files.put(
                src=str(self.source / filename),
                dest=f"{self.base}/provision/{filename}",
                mode="600",
                _sudo=True,
            )
        files.put(
            src=str(self.source / "docker-compose.yml"),
            dest=f"{self.base}/docker-compose.yml",
            mode="600",
            _sudo=True,
        )
        files.put(
            src=str(self.source / "Dockerfile"),
            dest=f"{self.base}/build/Dockerfile",
            mode="600",
            _sudo=True,
        )
        server.shell(
            name="Build Forgejo Runner 13.2.0 for Windows from upstream source",
            commands=(
                f"docker buildx build --output type=local,dest={self.base}/provision "
                f"{self.base}/build && chmod 600 {self.base}/provision/forgejo-runner.exe"
            ),
            _sudo=True,
        )

    def service(self):
        """Start the VM without waiting for the Windows installation to finish."""
        server.shell(
            name="Start Cloud Windows runner VM",
            commands=f"docker compose --project-directory {self.base} up -d",
            _sudo=True,
        )

    def remove(self):
        """Stop the VM while preserving its disk and registration."""
        server.shell(
            name="Stop Cloud Windows runner VM",
            commands=f"docker compose --project-directory {self.base} down",
            _sudo=True,
        )
