"""Barrett — Debian VPN torrent server.

Replaces scripts/barrett-setup.sh with declarative pyinfra deployment.
Deploy with: just barrett

Pre-requisites (place on host before running):
  /root/.nordvpn-token              — NordVPN login token
  /etc/mog-secrets                  — CIFS credentials for //192.168.1.167/titan
  /root/.qbittorrent-password       — qBittorrent plain-text password (autoremove)
  /root/.qbittorrent-password-hash  — qBittorrent PBKDF2 hash (WebUI)
"""

from modules.linux.programs.home_manager import HomeManagerModule
from modules.linux.services.autoremove_torrents import AutoremoveTorrentsModule
from modules.linux.services.ipfilter import IPFilterModule
from modules.linux.services.nordvpn import NordVPNModule
from modules.linux.services.qbittorrent import QBittorrentModule
from modules.linux.services.titan_mount import TitanMountModule

home_manager = HomeManagerModule(profile="server")
nordvpn = NordVPNModule(user="danny")
titan = TitanMountModule()
qbittorrent = QBittorrentModule(
    user="danny",
    config_dir="/var/lib/torrent/qbittorrent",
    download_dir="/mnt/titan/downloads",
    webui_port=8112,
    torrent_port=6881,
    upload_limit=100,
    download_limit=0,
    username="danny",
    password_hash_file="/root/.qbittorrent-password-hash",
)
autoremove = AutoremoveTorrentsModule(
    user="danny",
    webui_port=8112,
    username="danny",
    password_file="/root/.qbittorrent-password",
    interval_minutes=5,
    remove_rule="seeding_time > 600",
)
ipfilter = IPFilterModule()

home_manager.deploy()
nordvpn.deploy()
titan.deploy()
qbittorrent.deploy()
autoremove.deploy()
ipfilter.deploy()
