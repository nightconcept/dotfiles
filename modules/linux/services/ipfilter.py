"""qBittorrent IP filter updater module for host configuration."""

import io

from pyinfra.operations import files, server, systemd

from ..module import HostModule

_UPDATE_SCRIPT = """\
#!/usr/bin/env bash
set -euo pipefail

OUTPUT_FILE="/var/lib/torrent/qbittorrent/qBittorrent/data/ipfilter.dat"
TEMP_FILE=$(mktemp)
IPFILTER_URL="https://github.com/DavidMoore/ipfilter/releases/download/lists/ipfilter.dat"

# Skip if NordVPN is not connected — DNS only resolves through the tunnel.
if ! nordvpn status 2>/dev/null | grep -q "Status: Connected"; then
    echo "NordVPN not connected — deferring IP filter update"
    rm -f "$TEMP_FILE"
    exit 0
fi

echo "Downloading IP filter from GitHub..."

if curl -sSL "$IPFILTER_URL" -o "$TEMP_FILE" --connect-timeout 30 --max-time 300; then
    RULE_COUNT=$(wc -l < "$TEMP_FILE" 2>/dev/null || echo 0)
    if [ "$RULE_COUNT" -gt 0 ]; then
        mv "$TEMP_FILE" "$OUTPUT_FILE"
        chown danny:users "$OUTPUT_FILE"
        chmod 644 "$OUTPUT_FILE"
        echo "IP filter update complete! Rules: $RULE_COUNT"
    else
        echo "Error: downloaded file is empty"
        rm -f "$TEMP_FILE"
        exit 1
    fi
else
    echo "Error: failed to download IP filter"
    rm -f "$TEMP_FILE"
    exit 1
fi
"""

_SERVICE_UNIT = """\
[Unit]
Description=Update qBittorrent IP filters
After=network-online.target nordvpnd.service
Wants=network-online.target

[Service]
Type=oneshot
User=danny
ExecStart=/usr/local/bin/update-qbittorrent-ipfilter
Restart=on-failure
RestartSec=5min
StartLimitBurst=3
StartLimitIntervalSec=1h
"""

_TIMER_UNIT = """\
[Unit]
Description=Update qBittorrent IP filters every 24 hours

[Timer]
OnBootSec=5min
OnUnitActiveSec=24h
Unit=qbittorrent-ipfilter-update.service

[Install]
WantedBy=timers.target
"""


class IPFilterModule(HostModule):
    """Manages qBittorrent IP blocklist download and periodic refresh."""

    def install(self):
        """Nothing to pre-install — curl is expected to be present."""
        pass

    def update(self):
        """Write the update script to /usr/local/bin."""
        files.put(
            name="Deploy update-qbittorrent-ipfilter script",
            src=io.StringIO(_UPDATE_SCRIPT),
            dest="/usr/local/bin/update-qbittorrent-ipfilter",
            mode="755",
            _sudo=True,
        )

    def service(self):
        """Deploy systemd service and timer, then run an initial update."""
        files.put(
            name="Deploy qbittorrent-ipfilter-update.service unit",
            src=io.StringIO(_SERVICE_UNIT),
            dest="/etc/systemd/system/qbittorrent-ipfilter-update.service",
            mode="644",
            _sudo=True,
        )

        files.put(
            name="Deploy qbittorrent-ipfilter-update.timer unit",
            src=io.StringIO(_TIMER_UNIT),
            dest="/etc/systemd/system/qbittorrent-ipfilter-update.timer",
            mode="644",
            _sudo=True,
        )

        systemd.service(
            name="Enable qbittorrent-ipfilter-update.timer",
            service="qbittorrent-ipfilter-update.timer",
            running=True,
            enabled=True,
            daemon_reload=True,
            _sudo=True,
        )

        server.shell(
            name="Run initial IP filter update",
            commands=[
                "systemctl start qbittorrent-ipfilter-update.service || true"
            ],
            _sudo=True,
        )

    def remove(self):
        """Disable timer and remove the update script."""
        systemd.service(
            name="Disable qbittorrent-ipfilter-update.timer",
            service="qbittorrent-ipfilter-update.timer",
            running=False,
            enabled=False,
            _sudo=True,
        )
        files.file(
            name="Remove update-qbittorrent-ipfilter script",
            path="/usr/local/bin/update-qbittorrent-ipfilter",
            present=False,
            _sudo=True,
        )
