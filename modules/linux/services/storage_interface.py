"""Static interface on the isolated Locke storage network (plan 003).

The interface carries SMB traffic to Mog only. It has no gateway, no DHCP,
no IPv6, and no forwarding, so it cannot become a route to anywhere else.
Declaring it in ifupdown also makes NetworkManager leave it alone (see
IfupdownNetworkModule).
"""

import io

from pyinfra.operations import files, server

from ..module import HostModule


class StorageInterfaceModule(HostModule):
    """Configures one static, gateway-less storage interface."""

    def __init__(self, interface: str, address: str):
        """Initialize storage interface module.

        Args:
            interface: Guest interface on the storage bridge, such as ens19.
            address: Address with prefix length, such as 10.77.0.30/24.
        """
        self.interface = interface
        self.address = address
        self.path = f"/etc/network/interfaces.d/{interface}-storage"

    def install(self):
        """Nothing to install; ifupdown is part of the base system."""

    def update(self):
        """Write the ifupdown stanza."""
        i = self.interface
        stanza = (
            f"# Isolated storage network to Mog (plan 003). No gateway.\n"
            f"auto {i}\n"
            f"iface {i} inet static\n"
            f"    address {self.address}\n"
            f"    pre-up sysctl -q -w net.ipv6.conf.{i}.disable_ipv6=1\n"
            f"    post-up sysctl -q -w net.ipv4.conf.{i}.forwarding=0\n"
        )
        self.config = files.put(
            name=f"Declare storage interface {i}",
            src=io.StringIO(stanza),
            dest=self.path,
            mode="644",
            _sudo=True,
        )

    def service(self):
        """Release the interface from NetworkManager and bring it up."""
        server.shell(
            name=f"Bring up storage interface {self.interface}",
            commands=[
                "systemctl restart NetworkManager",
                f"ip addr flush dev {self.interface}",
                f"ifdown --force {self.interface} || true",
                f"ifup {self.interface}",
            ],
            _sudo=True,
            _if=self.config.did_change,
        )

    def remove(self):
        """Take the interface down and remove its stanza."""
        server.shell(
            name=f"Take down storage interface {self.interface}",
            commands=[f"ifdown --force {self.interface} || true"],
            _sudo=True,
        )
        files.file(
            name=f"Remove storage interface {self.interface}",
            path=self.path,
            present=False,
            _sudo=True,
        )
