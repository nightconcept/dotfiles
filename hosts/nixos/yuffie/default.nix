# Yuffie - nightly flake update builder and binary cache (Proxmox VM 100 on Valefor)
# It shares Valefor's 4 N100 cores with rinoa, so it builds at midnight and yields CPU
# to rinoa. Policy, VM settings and the reprovisioning runbook: docs/yuffie.md.
{
  config,
  lib,
  pkgs,
  ...
}: let
  secret = key: {
    sopsFile = ./secrets/secrets.yaml;
    inherit key;
  };
in {
  imports = [
    ./hardware-configuration.nix
  ];

  modules.nixos.networking.base.hostName = "yuffie";

  # BIOS VM: GRUB on the disk. Keep two boot entries, the current and the previous system.
  modules.nixos.core.bootloader.enable = false;
  boot.loader = {
    systemd-boot.enable = false;
    efi.canTouchEfiVariables = false;
    grub = {
      enable = true;
      device = "/dev/sda";
      configurationLimit = 2;
    };
  };

  modules.nixos = {
    kernel.type = "lts";

    network = {
      networkManager = true;
      mdns = true;
    };

    security.sops.enable = true;

    services.flakeUpdater = {
      enable = true;
      sshKeyFile = config.sops.secrets."yuffie/forgejo_deploy_key".path;
    };
  };

  # 6 GB RAM: compress swap in RAM for large link steps.
  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };

  nix = {
    settings = {
      # Two builds of two cores each leave room for rinoa on Valefor's four cores.
      max-jobs = lib.mkForce 2;
      cores = lib.mkForce 2;
      # Collect garbage during a build when the 120 GB disk runs low.
      min-free = 10 * 1024 * 1024 * 1024;
      max-free = 30 * 1024 * 1024 * 1024;
    };
    daemonCPUSchedPolicy = "batch";
    daemonIOSchedClass = "idle";
    # The flake updater roots the current and previous builds; collect the rest daily.
    # No age limit: preStart below keeps exactly two system generations.
    gc = {
      dates = lib.mkForce "daily";
      options = lib.mkForce "";
    };
  };

  # Keep the current and previous system generations only.
  systemd.services.nix-gc.preStart = ''
    ${config.nix.package}/bin/nix-env --profile /nix/var/nix/profiles/system --delete-generations +2
  '';

  # Binary cache: hosts can download the exact closures that passed the gate.
  services.harmonia.cache = {
    enable = true;
    signKeyPaths = [config.sops.secrets."yuffie/harmonia_sign_key".path];
  };
  networking.firewall.allowedTCPPorts = [5000];

  sops.secrets = {
    "yuffie/harmonia_sign_key" = secret "harmonia_sign_key";
    "yuffie/forgejo_deploy_key" =
      secret "forgejo_deploy_key"
      // {
        owner = "flake-updater";
        mode = "0400";
      };
  };

  environment.systemPackages = with pkgs; [
    home-manager
    nvd
  ];

  system.stateVersion = "26.11";
}
