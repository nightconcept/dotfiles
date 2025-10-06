# Main entry point for all NixOS modules
{
  imports = [
    ./kernel
    ./network
    ./services/plex
    ./services/nordvpn
    ./services/torrent

    # New modular architecture
    ./core
    ./hardware
    ./desktop
    ./storage
    ./networking
    ./programs
    ./services/docker
    ./services/openssh
    ./security
  ];
}
