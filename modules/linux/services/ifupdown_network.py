"""Keep a Debian interface under one DHCP client (ifupdown + dhcpcd).

NetworkManager's ifupdown plugin with ``managed=true`` runs its own DHCP
client on interfaces that ifupdown already configures through dhcpcd. The
router then sees two clients with one MAC and hands out two leases, so the
host answers on two addresses and either one can drift.
"""

import io

from pyinfra.operations import files, server

from ..module import HostModule

_CONFIG_PATH = "/etc/NetworkManager/conf.d/zz-ifupdown-unmanaged.conf"
_CONFIG = "[ifupdown]\nmanaged=false\n"
_CLEANUP_PATH = "/usr/local/sbin/drop-non-dhcpcd-addresses"

# Removes IPv4 addresses on the interface that dhcpcd does not hold. Runs as
# a transient unit so that an SSH session using a removed address can drop
# without interrupting the cleanup.
_CLEANUP_SCRIPT = """\
#!/usr/bin/env bash
set -euo pipefail

iface="$1"
keep=$(/usr/sbin/dhcpcd --dumplease -4 "$iface" 2>/dev/null \\
    | sed -nE "s/^ip_address='?([^']*)'?$/\\1/p")
if [[ -z "$keep" ]]; then
    echo "dhcpcd holds no lease on $iface; leaving addresses alone" >&2
    exit 0
fi

ip -4 -o addr show dev "$iface" scope global | awk '{print $4}' | while read -r cidr; do
    if [[ "${cidr%/*}" != "$keep" ]]; then
        echo "Removing $cidr from $iface (dhcpcd holds $keep)"
        ip addr del "$cidr" dev "$iface"
    fi
done
"""


class IfupdownNetworkModule(HostModule):
    """Leave ifupdown interfaces to dhcpcd and drop NetworkManager leases."""

    def __init__(self, interface: str):
        """Initialize ifupdown network module.

        Args:
            interface: The ifupdown interface that dhcpcd should own.
        """
        self.interface = interface

    def install(self):
        """ifupdown, dhcpcd, and NetworkManager are already installed."""

    def update(self):
        """Stop NetworkManager from managing ifupdown interfaces."""
        self.config = files.put(
            name="Leave ifupdown interfaces unmanaged by NetworkManager",
            src=io.StringIO(_CONFIG),
            dest=_CONFIG_PATH,
            mode="644",
            _sudo=True,
        )
        files.put(
            name="Deploy drop-non-dhcpcd-addresses script",
            src=io.StringIO(_CLEANUP_SCRIPT),
            dest=_CLEANUP_PATH,
            mode="755",
            _sudo=True,
        )

    def service(self):
        """Restart NetworkManager on change, then drop its stale lease."""
        server.shell(
            name="Restart NetworkManager to release ifupdown interfaces",
            commands=["systemctl restart NetworkManager"],
            _sudo=True,
            _if=self.config.did_change,
        )
        server.shell(
            name=f"Drop addresses on {self.interface} not held by dhcpcd",
            commands=[
                "systemd-run --collect --quiet --unit=drop-non-dhcpcd-addresses "
                f"--on-active=30 {_CLEANUP_PATH} {self.interface}"
            ],
            _sudo=True,
        )

    def remove(self):
        """Return interface management to the NetworkManager.conf setting."""
        files.file(
            name="Remove ifupdown unmanaged override",
            path=_CONFIG_PATH,
            present=False,
            _sudo=True,
        )
        files.file(
            name="Remove drop-non-dhcpcd-addresses script",
            path=_CLEANUP_PATH,
            present=False,
            _sudo=True,
        )
