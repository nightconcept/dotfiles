# Tidus - Dell Latitude 7420 laptop with Hyprland
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    inputs.nixos-hardware.nixosModules.dell-latitude-7420
  ];

  # Networking
  modules.nixos.networking.base.hostName = "tidus";

  # Desktop environment
  modules.nixos.desktop.hyprland.enable = true;

  services.logind.settings.Login = {
    HandleLidSwitch = "suspend";
    HandleLidSwitchExternalPower = "ignore";
  };

  # Hardware features
  modules.nixos.hardware = {
    bluetooth.enable = true;
    power.enable = true;
    sound.enable = true;
    graphics.enable = true;
    usbAutomount.enable = true;
  };

  # Storage
  modules.nixos.storage.networkDrives.enable = true;

  # Kernel configuration
  modules.nixos.kernel.type = "zen";

  # Programs
  modules.nixos.programs.nomachine.enable = true;
  modules.nixos.programs.steam.enable = true;

  # Services
  modules.nixos.docker.enable = true;

  # Vesper work (a foreman remote host), as on vincent.
  environment.systemPackages = with pkgs; [
    gcc # cgo: the Vesper site tests build with go
    python3 # the Vesper tests run some tools on the system python3
  ];

  # Vesper's tests and scripts name /bin/bash and /usr/bin/python3. envfs serves /bin and
  # /usr/bin from the caller's PATH, as on a plain Linux host.
  services.envfs.enable = true;

  # Foreman runs host jobs as user units: keep them alive with no login session.
  users.users.danny.linger = true;

  system.stateVersion = "23.11";
}
