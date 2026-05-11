"""qBittorrent module for host configuration."""

import io

from pyinfra.operations import files, server, systemd

from ..module import HostModule

_SERVICE_UNIT = """\
[Unit]
Description=qBittorrent-nox service
After=network.target mnt-titan.automount nordvpnd.service

[Service]
Type=simple
User={user}
Group=users
ExecStartPre=/bin/bash -c 'mkdir -p {config_dir}/qBittorrent/{{config,data/logs}}'
ExecStart=/usr/bin/qbittorrent-nox \\
    --confirm-legal-notice \\
    --webui-port={webui_port} \\
    --profile={config_dir} \\
    --save-path={download_dir}
Restart=on-failure
RestartSec=10s
PrivateTmp=true

[Install]
WantedBy=multi-user.target
"""

_QBITTORRENT_CONF = """\
[Application]
FileLogger\\Enabled=true
FileLogger\\Path={config_dir}/qBittorrent/data/logs

[BitTorrent]
Session\\AddTorrentStopped=false
Session\\AnonymousMode=true
Session\\AnonymousModeEnabled=true
Session\\DefaultSavePath={download_dir}
Session\\DHTEnabled=false
Session\\Encryption=1
Session\\GlobalMaxRatio=2.0
Session\\GlobalUPSpeedLimit={upload_limit}
Session\\GlobalDLSpeedLimit={download_limit}
Session\\Interface=nordlynx
Session\\InterfaceName=nordlynx
Session\\IPFilteringEnabled=true
Session\\IPFilterFile={config_dir}/qBittorrent/data/ipfilter.dat
Session\\IPFilterTrackers=true
Session\\LSDEnabled=false
Session\\MaxActiveDownloads=10
Session\\MaxActiveTorrents=10
Session\\MaxConnections=100
Session\\MaxConnectionsPerTorrent=50
Session\\PeXEnabled=false
Session\\Port={torrent_port}
Session\\QueueingSystemEnabled=true
Session\\RequireEncryption=true
Session\\SSL\\Port=62900
Session\\ShareLimitAction=Stop
Session\\UseRandomPort=false
Session\\uTPRateLimited=false

[LegalNotice]
Accepted=true

[Network]
Proxy\\HostnameLookupEnabled=false
Connection\\PortRangeMin={torrent_port}

[Preferences]
Bittorrent\\MaxUploadsPerTorrent=4
Downloads\\SavePath={download_dir}
General\\Locale=en
WebUI\\CSRFProtection=false
WebUI\\LocalHostAuth=false
WebUI\\Password_PBKDF2="@ByteArray({password_hash})"
WebUI\\Port={webui_port}
WebUI\\Username={username}

[RSS]
AutoDownloader\\DownloadRepacks=true
"""


class QBittorrentModule(HostModule):
    """Manages qBittorrent-nox installation and VPN-bound configuration."""

    def __init__(
        self,
        user: str = "danny",
        config_dir: str = "/var/lib/torrent/qbittorrent",
        download_dir: str = "/mnt/titan/downloads",
        webui_port: int = 8112,
        torrent_port: int = 6881,
        upload_limit: int = 100,
        download_limit: int = 0,
        username: str = "danny",
        password_hash_file: str = "/root/.qbittorrent-password-hash",
    ):
        """Initialize qBittorrent module parameters."""
        self.user = user
        self.config_dir = config_dir
        self.download_dir = download_dir
        self.webui_port = webui_port
        self.torrent_port = torrent_port
        self.upload_limit = upload_limit
        self.download_limit = download_limit
        self.username = username
        self.password_hash_file = password_hash_file

    def install(self):
        """Install qbittorrent-nox and create config directories."""
        server.shell(
            name="Install qbittorrent-nox (if missing)",
            commands=[
                "if ! dpkg -s qbittorrent-nox >/dev/null 2>&1; then "
                "apt-get update && apt-get install -y qbittorrent-nox; fi"
            ],
            _sudo=True,
        )

        for path in [
            f"{self.config_dir}/qBittorrent/config",
            f"{self.config_dir}/qBittorrent/cache",
            f"{self.config_dir}/qBittorrent/data/logs",
            self.download_dir,
        ]:
            files.directory(
                name=f"Ensure {path} exists",
                path=path,
                present=True,
                user=self.user,
                group="users",
                _sudo=True,
            )

        # Seed an empty ipfilter.dat so qBittorrent doesn't fail on first start
        files.file(
            name="Seed empty ipfilter.dat",
            path=f"{self.config_dir}/qBittorrent/data/ipfilter.dat",
            present=True,
            user=self.user,
            group="users",
            mode="644",
            _sudo=True,
        )

    def update(self):
        """Regenerate qBittorrent config from hash file."""
        server.shell(
            name="Write qBittorrent.conf from password hash file",
            commands=[
                f"""
                set -eu
                if [ ! -f "{self.password_hash_file}" ]; then
                    echo "WARNING: {self.password_hash_file} not found — config not written"
                    exit 0
                fi
                HASH=$(cat "{self.password_hash_file}")
                cat > {self.config_dir}/qBittorrent/config/qBittorrent.conf << CONF
[Application]
FileLogger\\Enabled=true
FileLogger\\Path={self.config_dir}/qBittorrent/data/logs

[BitTorrent]
Session\\AddTorrentStopped=false
Session\\AnonymousMode=true
Session\\AnonymousModeEnabled=true
Session\\DefaultSavePath={self.download_dir}
Session\\DHTEnabled=false
Session\\Encryption=1
Session\\GlobalMaxRatio=2.0
Session\\GlobalUPSpeedLimit={self.upload_limit}
Session\\GlobalDLSpeedLimit={self.download_limit}
Session\\Interface=nordlynx
Session\\InterfaceName=nordlynx
Session\\IPFilteringEnabled=true
Session\\IPFilterFile={self.config_dir}/qBittorrent/data/ipfilter.dat
Session\\IPFilterTrackers=true
Session\\LSDEnabled=false
Session\\MaxActiveDownloads=10
Session\\MaxActiveTorrents=10
Session\\MaxConnections=100
Session\\MaxConnectionsPerTorrent=50
Session\\PeXEnabled=false
Session\\Port={self.torrent_port}
Session\\QueueingSystemEnabled=true
Session\\RequireEncryption=true
Session\\SSL\\Port=62900
Session\\ShareLimitAction=Stop
Session\\UseRandomPort=false
Session\\uTPRateLimited=false

[LegalNotice]
Accepted=true

[Network]
Proxy\\HostnameLookupEnabled=false
Connection\\PortRangeMin={self.torrent_port}

[Preferences]
Bittorrent\\MaxUploadsPerTorrent=4
Downloads\\SavePath={self.download_dir}
General\\Locale=en
WebUI\\CSRFProtection=false
WebUI\\LocalHostAuth=false
WebUI\\Password_PBKDF2="@ByteArray($HASH)"
WebUI\\Port={self.webui_port}
WebUI\\Username={self.username}

[RSS]
AutoDownloader\\DownloadRepacks=true
CONF
                chown {self.user}:users {self.config_dir}/qBittorrent/config/qBittorrent.conf
                chmod 600 {self.config_dir}/qBittorrent/config/qBittorrent.conf
                echo "qBittorrent.conf written"
                """
            ],
            _sudo=True,
        )

    def service(self):
        """Deploy systemd service unit and (re)start qBittorrent."""
        unit = _SERVICE_UNIT.format(
            user=self.user,
            config_dir=self.config_dir,
            download_dir=self.download_dir,
            webui_port=self.webui_port,
        )

        files.put(
            name="Deploy qbittorrent.service unit",
            src=io.StringIO(unit),
            dest="/etc/systemd/system/qbittorrent.service",
            mode="644",
            _sudo=True,
        )

        systemd.service(
            name="Enable and start qbittorrent",
            service="qbittorrent",
            running=True,
            enabled=True,
            daemon_reload=True,
            _sudo=True,
        )

    def remove(self):
        """Stop service and purge qbittorrent-nox."""
        systemd.service(
            name="Stop qbittorrent",
            service="qbittorrent",
            running=False,
            enabled=False,
            _sudo=True,
        )
        server.shell(
            name="Purge qbittorrent-nox",
            commands=["apt-get purge -y qbittorrent-nox || true"],
            _sudo=True,
        )
