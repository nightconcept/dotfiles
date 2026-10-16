"""Docker module for host configuration."""

import io
import os

from pyinfra import host
from pyinfra.facts.server import Command
from pyinfra.operations import apt, files, server, systemd

from modules.linux.module import HostModule


class DockerModule(HostModule):
    """Manages Docker installation and configuration."""

    def install(self):
        """Install Docker using official repositories."""
        # Install prerequisites
        apt.packages(
            name="Install Docker prerequisites",
            packages=["ca-certificates", "curl", "gnupg"],
            update=True,
            _sudo=True,
        )

        distribution = host.get_fact(Command, command='. /etc/os-release && echo "$ID"')
        if distribution not in {"debian", "ubuntu"}:
            raise ValueError(f"Unsupported Docker distribution: {distribution}")
        codename = host.get_fact(Command, command='. /etc/os-release && echo "$VERSION_CODENAME"')
        architecture = host.get_fact(Command, command="dpkg --print-architecture")
        files.directory(path="/etc/apt/keyrings", mode="755", _sudo=True)
        files.download(
            name="Install Docker repository signing key",
            src=f"https://download.docker.com/linux/{distribution}/gpg",
            dest="/etc/apt/keyrings/docker.asc",
            mode="644",
            _sudo=True,
        )
        files.put(
            name="Configure Docker apt repository",
            src=io.StringIO(
                f"deb [arch={architecture} signed-by=/etc/apt/keyrings/docker.asc] "
                f"https://download.docker.com/linux/{distribution} {codename} stable\n"
            ),
            dest="/etc/apt/sources.list.d/docker.list",
            mode="644",
            _sudo=True,
        )

        # Install Docker Engine
        apt.packages(
            name="Install Docker Engine and Compose",
            packages=[
                "docker-ce",
                "docker-ce-cli",
                "containerd.io",
                "docker-buildx-plugin",
                "docker-compose-plugin",
            ],
            update=True,
            _sudo=True,
        )

    def update(self):
        """Ensure the current user is in the docker group."""
        user = os.environ.get("USER", "danny")
        server.shell(
            name=f"Add user {user} to docker group",
            commands=[f"usermod -aG docker {user}"],
            _sudo=True,
        )

    def service(self):
        """Ensure Docker service is running and enabled."""
        systemd.service(
            name="Enable and start Docker service",
            service="docker",
            running=True,
            enabled=True,
            _sudo=True,
        )

    def remove(self):
        """Remove Docker components."""
        apt.packages(
            name="Remove Docker Engine",
            packages=["docker-ce", "docker-ce-cli", "containerd.io"],
            present=False,
            _sudo=True,
        )
