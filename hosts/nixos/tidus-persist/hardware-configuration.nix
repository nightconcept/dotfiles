# Hardware configuration for Dell Latitude 7420
# Filesystem configuration is handled by disko.nix
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # Boot configuration
  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "thunderbolt"
    "nvme"
    "usb_storage"
    "sd_mod"
    "rtsx_pci_sdmmc"
  ];
  boot.initrd.kernelModules = [];
  boot.kernelModules = ["kvm-intel"];
  boot.extraModulePackages = [];

  # CPU
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # Platform
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # Networking
  networking.useDHCP = lib.mkDefault true;

  # Power management
  powerManagement.cpuFreqGovernor = lib.mkDefault "powersave";
}
