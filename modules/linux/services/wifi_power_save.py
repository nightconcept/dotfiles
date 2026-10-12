"""NetworkManager Wi-Fi power-saving policy for the Terra desktop."""

import io

from pyinfra.operations import files, server

from ..module import HostModule

_CONFIG_PATH = "/etc/NetworkManager/conf.d/zz-wifi-powersave-off.conf"
_OLD_CONFIG_PATH = "/etc/NetworkManager/conf.d/90-wifi-powersave-off.conf"
_CONFIG = "[connection]\nwifi.powersave=2\n"


class WiFiPowerSaveModule(HostModule):
    """Keep Wi-Fi power saving disabled across connections and reboots."""

    def install(self):
        """NetworkManager is already installed on Terra."""

    def update(self):
        """Override Ubuntu's default Wi-Fi power-saving setting."""
        files.put(
            name="Disable NetworkManager Wi-Fi power saving on Terra",
            src=io.StringIO(_CONFIG),
            dest=_CONFIG_PATH,
            mode="644",
            _sudo=True,
        )
        files.file(
            name="Remove superseded Wi-Fi power-saving override",
            path=_OLD_CONFIG_PATH,
            present=False,
            _sudo=True,
        )

    def service(self):
        """Load the policy without restarting NetworkManager."""
        server.shell(
            name="Reload NetworkManager configuration",
            commands=["nmcli general reload conf"],
            _sudo=True,
        )

    def remove(self):
        """Remove the Terra-specific override."""
        files.file(
            name="Remove NetworkManager Wi-Fi power-saving override",
            path=_CONFIG_PATH,
            present=False,
            _sudo=True,
        )
