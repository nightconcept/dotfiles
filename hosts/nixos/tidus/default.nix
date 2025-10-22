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

  system.stateVersion = "23.11";
}
