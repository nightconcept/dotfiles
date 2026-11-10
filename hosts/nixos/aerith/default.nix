# Aerith - Plex and media services
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ./tv-cleanup
  ];

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Networking
  modules.nixos.networking.base.hostName = "aerith";

  # Override bootloader for legacy BIOS (no EFI partition)
  boot.loader = {
    systemd-boot.enable = lib.mkForce false;
    efi.canTouchEfiVariables = lib.mkForce false;
    grub = {
      enable = true;
      device = "/dev/sda"; # Install GRUB to MBR
    };
  };

  # Existing modular configuration
  modules.nixos = {
    kernel.type = "lts";

    network = {
      networkManager = true;
      mdns = true;
    };

    # Hardware for server
    hardware.usbAutomount.enable = true;

    # Network storage
    storage.networkDrives = {
      enable = true;
      enableTitan = true;
      # Isolated Locke storage network; traffic stays on the hypervisor.
      titanSource = "//10.77.0.10/titan";
      # Containers that require this mount stop when the idle timeout unmounts it.
      titanIdleTimeout = 0;
    };

    # Security
    security.sops.enable = true;
  };

  # Isolated storage network to Mog on Locke vmbr3 (plan 003). No gateway,
  # no DHCP, no IPv6, and no forwarding on this interface.
  networking.networkmanager.unmanaged = ["interface-name:ens19"];
  networking.interfaces.ens19 = {
    useDHCP = false;
    ipv4.addresses = [
      {
        address = "10.77.0.20";
        prefixLength = 24;
      }
    ];
  };
  boot.kernel.sysctl = {
    "net.ipv4.conf.ens19.forwarding" = 0;
    "net.ipv6.conf.ens19.disable_ipv6" = 1;
  };

  # Media services moved from Rinoa (plan 003). Their state is on local disk;
  # media and downloads stay on Titan.
  modules.nixos.docker.enable = true;

  modules.nixos.docker.containers = {
    jellyfin.enable = true;
    # Replaces the NixOS Plex service; uses its data directory in place.
    plex.enable = true;
    sonarr.enable = true;
    sonarr-anime.enable = true;
    radarr.enable = true;
    # Reads the *arr API keys from their local config.xml files.
    recyclarr.enable = true;
    watchtower = {
      enable = true;
      schedule = "0 0 4 * * *";
    };
  };

  modules.nixos.services.downloadSweeper = {
    enable = true;
    schedule = "hourly";
  };

  modules.nixos.docker.healthCheck = {
    enable = true;
    listenAddress = "192.168.1.118";
    expectedContainers = [
      "plex"
      "jellyfin"
      "sonarr"
      "sonarr-anime"
      "radarr"
      "recyclarr"
      "watchtower"
    ];
    mounts = ["/mnt/titan"];
    httpChecks = [
      {
        name = "Plex direct";
        url = "http://127.0.0.1:32400/identity";
      }
      {
        name = "Jellyfin direct";
        url = "http://127.0.0.1:8096/health";
      }
      {
        name = "Sonarr direct";
        url = "http://127.0.0.1:8989/ping";
      }
      {
        name = "Sonarr Anime direct";
        url = "http://127.0.0.1:8990/ping";
      }
      {
        name = "Radarr direct";
        url = "http://127.0.0.1:7878/ping";
      }
    ];
    afterUnits = [
      "docker-container-plex.service"
      "docker-container-jellyfin.service"
      "docker-container-sonarr.service"
      "docker-container-sonarr-anime.service"
      "docker-container-radarr.service"
      "docker-container-recyclarr.service"
      "docker-container-watchtower.service"
    ];
  };

  services.openssh.enable = true;

  # System packages for server management
  environment.systemPackages = with pkgs; [
    home-manager
  ];

  system.stateVersion = "23.11";
}
