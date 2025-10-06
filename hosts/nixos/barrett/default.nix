# Barrett - VPN torrent server
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
  ];

  # Networking
  modules.nixos.networking.base.hostName = "barrett";

  # Override bootloader for legacy BIOS (no EFI partition)
  boot.loader = {
    systemd-boot.enable = lib.mkForce false;
    efi.canTouchEfiVariables = lib.mkForce false;
    grub = {
      enable = true;
      device = "/dev/sda"; # Install GRUB to MBR
    };
  };

  # Explicitly allow unfree packages
  nixpkgs.config.allowUnfree = true;

  modules.nixos = {
    kernel.type = "lts";

    network = {
      networkManager = true;
      mdns = true;
    };

    # Mount titan network drive for downloads
    storage.networkDrives = {
      enable = true;
      enableTitan = true;
    };

    # NordVPN service using official client - all optimal defaults
    services.nordvpn = {
      enable = true;
      user = "danny";
      tokenFile = config.sops.secrets."vpn/nordvpn_token".path;
      # All other settings use optimal defaults:
      # - server = null (auto P2P servers)
      # - killSwitch = true
      # - autoConnect = true
      # - protocol = "NordLynx"
      # - dns = NordVPN DNS servers
    };

    # Torrent service with privacy settings - minimal config
    services.torrent = {
      enable = true;
      user = "danny";
      downloadDir = "/mnt/titan/downloads";

      qbittorrent = {
        webUIPort = 8112;
        username = "danny";
        passwordFile = config.sops.secrets."vpn/qbittorrent_password".path;
        passwordHashFile = config.sops.secrets."vpn/qbittorrent_password_hash".path;
        # All privacy settings and VPN binding use secure defaults
      };

      autoremove = {
        intervalMinutes = 5;
        strategies = {
          minimal_seed_strategy = {
            remove = "seeding_time > 600"; # 10 minutes
            delete_data = true;
          };
        };
      };

      # IP filter for blocking malicious peers
      ipfilter = {
        enable = true;
        updateIntervalHours = 24; # Update daily
      };
    };
  };

  # System packages for server management
  environment.systemPackages = with pkgs; [
    home-manager
  ];

  system.stateVersion = "24.11";
}
