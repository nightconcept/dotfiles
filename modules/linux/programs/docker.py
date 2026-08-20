"""Docker module for host configuration."""

import os
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

        # Add Docker's official GPG key and apt repository
        server.shell(
            name="Configure Docker apt repository",
            commands=[
                "install -m 0755 -d /etc/apt/keyrings",
                "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes",
                "chmod a+r /etc/apt/keyrings/docker.gpg",
                'echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null'
            ],
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
