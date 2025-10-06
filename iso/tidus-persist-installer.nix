# Custom NixOS installer ISO for tidus-persist with disko and impermanence
{
  config,
  pkgs,
  lib,
  modulesPath,
  ...
}: {
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
  ];

  # ISO naming
  image.fileName = lib.mkForce "tidus-persist-installer.iso";
  isoImage.volumeID = lib.mkForce "TIDUS_PERSIST";
  isoImage.makeEfiBootable = true;
  isoImage.makeUsbBootable = true;

  # Enable SSH for remote install
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      # Allow password auth for installer
      PasswordAuthentication = true;
    };
  };

  # Set a default root password for the installer
  # CHANGE THIS or use ssh keys instead!
  users.users.root.initialPassword = "nixos";

  # Include useful packages in the installer
  environment.systemPackages = with pkgs; [
    # Partitioning and filesystem tools
    disko
    parted
    gptfdisk
    cryptsetup
    btrfs-progs

    # Editor and tools
    vim
    git
    tmux
    htop
    ncdu

    # Network tools
    curl
    wget
    networkmanager

    # Hardware tools
    pciutils
    usbutils
    dmidecode
    lshw

    # For Dell firmware updates
    fwupd

    # Nix tools
    nix-output-monitor
    nixos-option
  ];

  # Enable NetworkManager for WiFi
  networking.networkmanager.enable = true;
  networking.wireless.enable = false;

  # Include our flake in the installer
  environment.etc."nixos-config/flake.nix".source = ../flake.nix;
  environment.etc."nixos-config/flake.lock".source = ../flake.lock;

  # Install script
  environment.etc."install-tidus-persist.sh" = {
    mode = "0755";
    text = ''
      #!/usr/bin/env bash
      set -e

      echo "==================================="
      echo "Tidus-Persist NixOS Installer with Impermanence"
      echo "==================================="
      echo
      echo "This will ERASE the target disk and install NixOS with:"
      echo "- BTRFS with LUKS encryption"
      echo "- Impermanence (ephemeral root)"
      echo "- Disko declarative partitioning"
      echo

      # Ask for target disk
      echo "Available disks:"
      lsblk -d -o NAME,SIZE,MODEL
      echo
      read -p "Enter target disk (e.g., nvme0n1, sda): " DISK
      DISK_PATH="/dev/$DISK"

      if [ ! -b "$DISK_PATH" ]; then
        echo "Error: $DISK_PATH is not a valid block device"
        exit 1
      fi

      echo
      echo "WARNING: This will COMPLETELY ERASE $DISK_PATH"
      read -p "Type 'yes' to continue: " CONFIRM

      if [ "$CONFIRM" != "yes" ]; then
        echo "Installation cancelled"
        exit 1
      fi

      # Get disk encryption password
      echo
      echo "Enter disk encryption password:"
      read -s DISK_PASSWORD
      echo "Confirm disk encryption password:"
      read -s DISK_PASSWORD_CONFIRM

      if [ "$DISK_PASSWORD" != "$DISK_PASSWORD_CONFIRM" ]; then
        echo "Passwords do not match"
        exit 1
      fi

      # Clone the dotfiles repo if not present
      if [ ! -d /tmp/dotfiles-nix ]; then
        echo "Cloning dotfiles repository..."
        git clone https://github.com/nightconcept/dotfiles-nix.git /tmp/dotfiles-nix
        cd /tmp/dotfiles-nix
        # Check out the impermanence branch
        git checkout feat/tidus-impermanence || git checkout main
      else
        cd /tmp/dotfiles-nix
        git pull
      fi

      # Run disko to partition and format
      echo
      echo "Running disko to partition and format disk..."
      echo "$DISK_PASSWORD" | nix run github:nix-community/disko/latest -- \
        --mode destroy,format,mount \
        --flake .#tidus-persist \
        --arg device "\"$DISK_PATH\""

      # Generate hardware configuration
      echo "Generating hardware configuration..."
      nixos-generate-config --root /mnt --no-filesystems

      # Copy the hardware configuration
      cp /mnt/etc/nixos/hardware-configuration.nix hosts/nixos/tidus/hardware-configuration-new.nix

      # Install NixOS
      echo "Installing NixOS..."
      nixos-install --flake .#tidus-persist --no-root-password

      # Set root password in installed system
      echo "Setting root password in installed system..."
      echo "$DISK_PASSWORD" | nixos-enter -- passwd --stdin root

      echo
      echo "==================================="
      echo "Installation complete!"
      echo "==================================="
      echo
      echo "Next steps:"
      echo "1. Remove installation media and reboot"
      echo "2. Login as root with the password you set"
      echo "3. Create your user account if needed"
      echo "4. Optionally set up FIDO2/YubiKey for LUKS"
      echo
      echo "To skip root rollback once (for debugging):"
      echo "  touch /persist-once"
      echo
    '';
  };

  # Convenience aliases
  programs.bash.shellAliases = {
    install-tidus-persist = "/etc/install-tidus-persist.sh";
  };

  # Message on boot
  services.getty.helpLine = ''

    === Tidus-Persist NixOS Installer ===

    To install: run 'install-tidus-persist'

    Default root password: nixos
    WiFi: use 'nmtui' to connect

  '';

  # Ensure we boot with all needed modules
  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "thunderbolt"
    "nvme"
    "usb_storage"
    "sd_mod"
    "rtsx_pci_sdmmc"
    "aesni-intel"
    "cryptd"
  ];

  boot.kernelModules = ["kvm-intel"];

  # Use latest kernel for best hardware support
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Enable firmware for WiFi
  hardware.enableRedistributableFirmware = true;

  system.stateVersion = "24.05";
}
