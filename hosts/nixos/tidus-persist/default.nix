# Tidus-Persist - Dell Latitude 7420 laptop with Hyprland + Impermanence
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ./impermanence.nix
    ./recovery.nix
    inputs.nixos-hardware.nixosModules.dell-latitude-7420
    inputs.disko.nixosModules.disko
    inputs.impermanence.nixosModules.impermanence
  ];

  # Networking
  modules.nixos.networking.base.hostName = "tidus-persist";

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

  system.stateVersion = "23.11";
}
