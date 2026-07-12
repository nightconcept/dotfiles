"""Foreign-architecture execution support for pyinfra-managed Linux hosts."""

from pyinfra.operations import apt, server, systemd

from modules.linux.module import HostModule


class ForeignArchModule(HostModule):
    """Enables transparent AArch64 execution for local Nix builds."""

    def __init__(self, arch: str = "aarch64-linux"):
        self.arch = arch

    def install(self):
        """Install the distro-side binfmt integration for QEMU user emulation."""
        apt.packages(
            name="Install QEMU binfmt support for foreign-arch execution",
            packages=["qemu-user-binfmt", "qemu-user-static"],
            update=True,
            _sudo=True,
        )

    def update(self):
        """Ensure the Nix daemon advertises the foreign platform."""
        server.shell(
            name=f"Enable {self.arch} in /etc/nix/nix.conf",
            commands=[
                f"""
if grep -q '^extra-platforms = ' /etc/nix/nix.conf; then
    if ! grep -Eq '^extra-platforms = .*\\b{self.arch}\\b' /etc/nix/nix.conf; then
        sed -i -E '/^extra-platforms = / s/$/ {self.arch}/' /etc/nix/nix.conf
        systemctl restart nix-daemon
    fi
else
    printf '\\nextra-platforms = {self.arch}\\n' >> /etc/nix/nix.conf
    systemctl restart nix-daemon
fi
""".strip()
            ],
            _sudo=True,
        )

    def service(self):
        """Ensure binfmt registrations are loaded."""
        systemd.service(
            name="Enable and start systemd-binfmt",
            service="systemd-binfmt",
            running=True,
            enabled=True,
            _sudo=True,
        )

    def remove(self):
        """Remove foreign-arch execution support."""
        apt.packages(
            name="Remove QEMU binfmt support",
            packages=["qemu-user-binfmt", "qemu-user-static"],
            present=False,
            _sudo=True,
        )
