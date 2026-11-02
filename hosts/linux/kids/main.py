"""Kids — Arch-based Linux desktop.

Deploy the complete host with: just kids

Pre-requisite: the personal age key at ~/.config/sops/age/keys.txt (bootstrap.sh
installs it). Titan credentials are decrypted from SOPS into /etc/mog-secrets.
"""

from modules.linux.programs.home_manager import HomeManagerModule
from modules.linux.services.titan_mount import TitanMountModule

home_manager = HomeManagerModule(profile="desktop")
home_manager.install()
home_manager.update()

TitanMountModule().deploy()
