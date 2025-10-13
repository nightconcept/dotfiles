# Vincent - CI/CD Runner Host
# Purpose: Container orchestration for GitHub and Forgejo runners
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
  modules.nixos.networking.base.hostName = "vincent";

  # Bootloader configuration (override systemd-boot for BIOS/MBR systems)
  modules.nixos.core.bootloader.enable = false;
  boot.loader = {
    systemd-boot.enable = false;
    efi.canTouchEfiVariables = false;
    grub = {
      enable = true;
      device = "/dev/sda"; # Update this to match your actual disk
    };
  };

  # Standard NixOS modules
  modules.nixos = {
    kernel.type = "lts";

    network = {
      networkManager = true;
      mdns = true;
    };

    # Enable SOPS for secrets management
    security.sops.enable = true;
  };

  # System packages for server management
  environment.systemPackages = with pkgs; [
    home-manager
  ];

  # Enable Docker module with Swarm support for Dokploy
  modules.nixos.docker = {
    enable = true;
    # Dokploy requires Docker Swarm which needs live-restore disabled
    swarm.enable = true;
  };

  # Forgejo Runners
  modules.nixos.docker.containers.forgejo-runner = {
    enable = true;
    replicas = 3;
    labels = ["docker" "amd64" "linux" "vincent" "ubuntu-latest"];
  };

  # Additional container management
  modules.nixos.docker.containers = {
    # Container management
    portainer = {
      enable = true;
      port = 9000;
    };

    # Auto-update containers (optional)
    watchtower = {
      enable = false; # Disabled by default for CI runners
      schedule = "0 0 4 * * *";
    };
  };

  # System state version
  system.stateVersion = "24.11";
}
