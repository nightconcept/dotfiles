"""Barrett — Debian VPN torrent and Usenet server.

Replaces scripts/barrett-setup.sh with declarative pyinfra deployment.
Deploy with: just barrett

Pre-requisites (place on host before running):
  /root/.nordvpn-token              — NordVPN login token
  /etc/mog-secrets                  — CIFS credentials for the Titan share on Mog
  /root/.qbittorrent-password       — qBittorrent plain-text password (autoremove)
  /root/.qbittorrent-password-hash  — qBittorrent PBKDF2 hash (WebUI)
"""

from modules.linux.programs.home_manager import HomeManagerModule
from modules.linux.services.autoremove_torrents import AutoremoveTorrentsModule
from modules.linux.services.ifupdown_network import IfupdownNetworkModule
from modules.linux.services.ipfilter import IPFilterModule
from modules.linux.services.nordvpn import NordVPNModule
from modules.linux.services.qbittorrent import QBittorrentModule
from modules.linux.services.sabnzbd import SABnzbdModule
from modules.linux.services.storage_interface import StorageInterfaceModule
from modules.linux.services.titan_mount import TitanMountModule
from modules.linux.services.unattended_upgrades import UnattendedUpgradesModule

home_manager = HomeManagerModule(profile="server")
nordvpn = NordVPNModule(user="danny")
# Titan through the isolated Locke storage network (plan 003).
storage = StorageInterfaceModule(interface="ens19", address="10.77.0.30/24")
titan = TitanMountModule(source="//10.77.0.10/titan")
sabnzbd = SABnzbdModule()
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
network = IfupdownNetworkModule(interface="ens18")
unattended_upgrades = UnattendedUpgradesModule()

unattended_upgrades.deploy()

home_manager.deploy()
nordvpn.deploy()
storage.deploy()
titan.deploy()
qbittorrent.deploy()
sabnzbd.deploy()
autoremove.deploy()
ipfilter.deploy()
# Last: dropping the NetworkManager lease can end SSH sessions using it.
network.deploy()
