"""Distro-aware system package installation for pyinfra hosts."""

from pyinfra import host
from pyinfra.facts.server import Which
from pyinfra.operations import apt, pacman


def is_arch() -> bool:
    """Return True when the host uses pacman (Arch and derivatives)."""
    return bool(host.get_fact(Which, command="pacman"))


def install_packages(name: str, debian: list[str], arch: list[str] | None = None):
    """Install system packages with the host's package manager.

    Args:
        name: Operation name shown by pyinfra.
        debian: Package names for apt hosts.
        arch: Package names for pacman hosts. Defaults to the Debian names.
    """
    if is_arch():
        pacman.packages(name=name, packages=arch or debian, _sudo=True)
    else:
        apt.packages(name=name, packages=debian, update=True, cache_time=3600, _sudo=True)
