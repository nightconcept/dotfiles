"""SSH module for host configuration."""

from pyinfra.operations import apt, systemd

from modules.linux.module import HostModule


class SSHModule(HostModule):
    """Manages SSH server installation and configuration."""

    def install(self):
        """Ensure openssh-server is installed."""
        apt.packages(
            name="Install OpenSSH Server",
            packages=["openssh-server"],
            update=True,
            _sudo=True,
        )

    def update(self):
        """No specific update logic for SSH."""
        pass

    def service(self):
        """Ensure SSH service is running and enabled."""
        systemd.service(
            name="Enable and start SSH service",
            service="ssh",
            running=True,
            enabled=True,
            _sudo=True,
        )

    def remove(self):
        """Remove SSH server."""
        apt.packages(
            name="Remove OpenSSH Server",
            packages=["openssh-server"],
            present=False,
            _sudo=True,
        )
