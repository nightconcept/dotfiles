"""Bring Terra's Wi-Fi back when its USB adapter's firmware hangs."""

import io

from pyinfra.operations import files, systemd

from ..module import HostModule

_SCRIPT_PATH = "/usr/local/sbin/wifi-watchdog"
_SERVICE_PATH = "/etc/systemd/system/wifi-watchdog.service"
_TIMER_PATH = "/etc/systemd/system/wifi-watchdog.timer"

# The rtw88_8822bu adapter can stop answering ("failed to get tx report from firmware").
# NetworkManager then treats the failure as bad secrets, finds no agent to ask, and stops
# autoconnecting. Reloading the driver and activating the device by hand recovers it without a
# reboot.
_SCRIPT = """#!/bin/bash
set -u
STATE=/run/wifi-watchdog.fails
DRIVER={driver}
gw=$(ip -4 route show default | awk '{{print $3; exit}}')
if ping -c 3 -W 2 "${{gw:-{fallback_gateway}}}" >/dev/null 2>&1; then
  rm -f "$STATE"
  exit 0
fi
fails=$(( $(cat "$STATE" 2>/dev/null || echo 0) + 1 ))
echo "$fails" > "$STATE"
[ "$fails" -lt {threshold} ] && exit 0
logger -t wifi-watchdog "gateway unreachable for $fails checks; reloading $DRIVER"
modprobe -r "$DRIVER" && sleep 2 && modprobe "$DRIVER"
sleep 10
dev=$(nmcli -t -f DEVICE,TYPE device | awk -F: '$2=="wifi"{{print $1; exit}}')
[ -n "$dev" ] && nmcli device connect "$dev" >/dev/null 2>&1
echo 0 > "$STATE"
"""

_SERVICE = f"""[Unit]
Description=Recover Wi-Fi when the gateway stops answering
After=NetworkManager.service

[Service]
Type=oneshot
ExecStart={_SCRIPT_PATH}
"""

_TIMER = """[Unit]
Description=Check Wi-Fi every minute

[Timer]
OnBootSec=3min
OnUnitActiveSec=1min

[Install]
WantedBy=timers.target
"""


class WiFiWatchdogModule(HostModule):
    """Reload the Wi-Fi driver after the gateway has been unreachable for a few minutes."""

    def __init__(self, driver="rtw88_8822bu", threshold=3, fallback_gateway="192.168.1.1"):
        """Configure the watchdog.

        Args:
            driver: Kernel module of the Wi-Fi adapter to reload.
            threshold: Failed one-minute checks before the driver is reloaded.
            fallback_gateway: Address to ping when there is no default route.
        """
        self.driver = driver
        self.threshold = threshold
        self.fallback_gateway = fallback_gateway

    def install(self):
        """NetworkManager and kmod are already installed on Terra."""

    def update(self):
        """Install the watchdog script."""
        script = _SCRIPT.format(
            driver=self.driver, threshold=self.threshold, fallback_gateway=self.fallback_gateway
        )
        files.put(
            name="Install the Wi-Fi watchdog script",
            src=io.StringIO(script),
            dest=_SCRIPT_PATH,
            mode="755",
            _sudo=True,
        )

    def service(self):
        """Run the watchdog every minute."""
        files.put(
            name="Deploy wifi-watchdog.service unit",
            src=io.StringIO(_SERVICE),
            dest=_SERVICE_PATH,
            mode="644",
            _sudo=True,
        )
        files.put(
            name="Deploy wifi-watchdog.timer unit",
            src=io.StringIO(_TIMER),
            dest=_TIMER_PATH,
            mode="644",
            _sudo=True,
        )
        systemd.service(
            name="Enable wifi-watchdog.timer",
            service="wifi-watchdog.timer",
            running=True,
            enabled=True,
            daemon_reload=True,
            _sudo=True,
        )

    def remove(self):
        """Disable the timer and remove the watchdog."""
        systemd.service(
            name="Disable wifi-watchdog.timer",
            service="wifi-watchdog.timer",
            running=False,
            enabled=False,
            _sudo=True,
        )
        for path in (_TIMER_PATH, _SERVICE_PATH, _SCRIPT_PATH):
            files.file(name=f"Remove {path}", path=path, present=False, _sudo=True)
