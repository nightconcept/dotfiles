"""Unattended-upgrades module for host configuration."""

import io

from pyinfra.operations import apt, files

from ..module import HostModule

_APT_CONF_PATH = "/etc/apt/apt.conf.d/20auto-upgrades"


class UnattendedUpgradesModule(HostModule):
    """Manages automatic APT package upgrades.

    Installs unattended-upgrades and writes the periodic-upgrades apt config.
    Automatic reboot after an upgrade is disabled by default.
    """

    def __init__(
        self,
        update_package_lists_days: int = 1,
        unattended_upgrade_days: int = 1,
        auto_reboot: bool = False,
    ):
        """Configure periodic APT behavior.

        Args:
            update_package_lists_days: Days between apt-list refreshes (0
                disables).
            unattended_upgrade_days: Days between upgrade runs (0 disables).
            auto_reboot: Reboot automatically when an upgrade requires it.
        """
        self._update_package_lists_days = update_package_lists_days
        self._unattended_upgrade_days = unattended_upgrade_days
        self._auto_reboot = auto_reboot

    def install(self):
        """Install the unattended-upgrades package."""
        apt.packages(
            name="Install unattended upgrades",
            packages=["unattended-upgrades"],
            _sudo=True,
        )

    def update(self):
        """Write the periodic-upgrades apt config."""
        config = io.StringIO(
            f'APT::Periodic::Update-Package-Lists "{self._update_package_lists_days}";\n'
            f'APT::Periodic::Unattended-Upgrade "{self._unattended_upgrade_days}";\n'
            f'Unattended-Upgrade::Automatic-Reboot "{"true" if self._auto_reboot else "false"}";\n'
        )
        files.put(
            name="Enable daily unattended upgrades",
            src=config,
            dest=_APT_CONF_PATH,
            mode="644",
            _sudo=True,
        )

    def remove(self):
        """Remove the apt config and the package."""
        files.file(
            name="Remove periodic-upgrades apt config",
            path=_APT_CONF_PATH,
            present=False,
            _sudo=True,
        )
        apt.packages(
            name="Remove unattended upgrades",
            packages=["unattended-upgrades"],
            present=False,
            _sudo=True,
        )
