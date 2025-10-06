# Recovery and safety options for tidus impermanence setup
{
  config,
  pkgs,
  lib,
  ...
}: {
  # Boot menu entries for recovery
  boot.loader.grub.extraEntries = lib.mkIf config.boot.loader.grub.enable ''
    menuentry "NixOS - Skip Root Rollback" {
      linux /boot/vmlinuz init.skipRollback=1
      initrd /boot/initrd
    }
  '';

  boot.loader.systemd-boot.extraEntries = lib.mkIf config.boot.loader.systemd-boot.enable {
    "nixos-no-rollback.conf" = ''
      title NixOS - Skip Root Rollback
      linux /EFI/nixos/kernel.efi
      initrd /EFI/nixos/initrd.efi
      options init=/nix/store/.../init init.skipRollback=1
    '';
  };

  # Recovery tools in system packages
  environment.systemPackages = with pkgs; [
    # BTRFS recovery tools
    btrfs-progs
    compsize # Check compression ratio

    # Recovery script
    (writeShellScriptBin "tidus-recovery" ''
      #!/usr/bin/env bash
      set -e

      echo "Tidus Recovery Tool"
      echo "==================="
      echo
      echo "1. Mount persist for inspection"
      echo "2. Disable rollback for next boot"
      echo "3. Create BTRFS snapshot"
      echo "4. Restore BTRFS snapshot"
      echo "5. Check BTRFS filesystem"
      echo "6. Emergency chroot"
      echo
      read -p "Select option (1-6): " option

      case $option in
        1)
          echo "Mounting /persist read-only for inspection..."
          mkdir -p /tmp/persist-inspect
          mount -o ro,subvol=persist /dev/mapper/cryptroot /tmp/persist-inspect
          echo "Mounted at /tmp/persist-inspect"
          ;;
        2)
          echo "Creating persist-once marker..."
          touch /persist-once
          echo "Rollback disabled for next boot only"
          ;;
        3)
          read -p "Enter snapshot name: " snapname
          btrfs subvolume snapshot / "/persist/snapshots/root-$snapname"
          echo "Snapshot created at /persist/snapshots/root-$snapname"
          ;;
        4)
          echo "Available snapshots:"
          ls -la /persist/snapshots/
          read -p "Enter snapshot name to restore: " snapname
          echo "WARNING: This will replace current root!"
          read -p "Type 'yes' to continue: " confirm
          if [ "$confirm" == "yes" ]; then
            # This would need to be done from initrd or live system
            echo "Please boot from recovery media to restore snapshot"
            echo "Commands to run:"
            echo "  mount -t btrfs /dev/mapper/cryptroot /mnt"
            echo "  btrfs subvolume delete /mnt/root"
            echo "  btrfs subvolume snapshot /mnt/persist/snapshots/root-$snapname /mnt/root"
          fi
          ;;
        5)
          echo "Checking BTRFS filesystem..."
          btrfs filesystem show
          btrfs filesystem df /
          btrfs subvolume list /
          ;;
        6)
          echo "For emergency chroot:"
          echo "1. Boot from NixOS installer"
          echo "2. cryptsetup open /dev/nvme0n1p2 cryptroot"
          echo "3. mount -o subvol=root /dev/mapper/cryptroot /mnt"
          echo "4. mount -o subvol=nix /dev/mapper/cryptroot /mnt/nix"
          echo "5. mount -o subvol=persist /dev/mapper/cryptroot /mnt/persist"
          echo "6. mount /dev/nvme0n1p1 /mnt/boot"
          echo "7. nixos-enter"
          ;;
      esac
    '')

    # Persist state inspection tool
    (writeShellScriptBin "tidus-persist-check" ''
      #!/usr/bin/env bash
      echo "Checking persist usage..."
      echo
      echo "=== Disk Usage ==="
      df -h /persist
      echo
      echo "=== Top directories by size ==="
      du -sh /persist/* 2>/dev/null | sort -hr | head -20
      echo
      echo "=== Recently modified files ==="
      find /persist -type f -mtime -1 2>/dev/null | head -20
      echo
      echo "=== BTRFS compression ratio ==="
      compsize /persist
    '')

    # Emergency backup script
    (writeShellScriptBin "tidus-backup" ''
      #!/usr/bin/env bash
      set -e

      BACKUP_DATE=$(date +%Y%m%d-%H%M%S)
      BACKUP_DIR="/persist/backups/$BACKUP_DATE"

      echo "Creating backup at $BACKUP_DIR..."
      mkdir -p "$BACKUP_DIR"

      # Backup critical user data
      echo "Backing up user data..."
      rsync -av --progress \
        /persist/home/danny/.ssh \
        /persist/home/danny/.gnupg \
        /persist/home/danny/git \
        /persist/home/danny/Documents \
        "$BACKUP_DIR/"

      # Backup system configuration
      echo "Backing up system config..."
      cp -r /persist/etc/NetworkManager/system-connections "$BACKUP_DIR/"
      cp /persist/etc/machine-id "$BACKUP_DIR/"

      # Create tarball
      echo "Creating compressed archive..."
      tar -czf "/persist/backups/tidus-backup-$BACKUP_DATE.tar.gz" -C "$BACKUP_DIR" .
      rm -rf "$BACKUP_DIR"

      echo "Backup complete: /persist/backups/tidus-backup-$BACKUP_DATE.tar.gz"
      ls -lh "/persist/backups/"
    '')
  ];

  # Safety: Ensure we can always boot even if rollback fails
  boot.initrd.systemd.services.rollback-root = lib.mkForce {
    description = "Rollback BTRFS root subvolume to blank state";
    wantedBy = ["initrd.target"];
    after = ["device-dev-mapper-cryptroot.device"];
    before = ["sysroot.mount"];
    unitConfig = {
      DefaultDependencies = "no";
      # Don't fail boot if rollback fails
      OnFailure = "emergency.target";
    };
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      # Check for skip parameter
      if grep -q 'init.skipRollback=1' /proc/cmdline; then
        echo "Skipping rollback due to kernel parameter"
        exit 0
      fi

      mkdir -p /mnt

      # Try to mount; if it fails, still continue boot
      if ! mount -t btrfs -o subvol=/ /dev/mapper/cryptroot /mnt; then
        echo "WARNING: Failed to mount BTRFS root, skipping rollback"
        exit 0
      fi

      # Check if we should skip rollback
      if [ -e /mnt/root/persist-once ]; then
        echo "Found persist-once marker, skipping rollback"
        rm -f /mnt/root/persist-once
        umount /mnt
        exit 0
      fi

      # Try rollback but don't fail if it doesn't work
      (
        # Delete subvolumes under root
        btrfs subvolume list -o /mnt/root 2>/dev/null |
        while read -r line; do
          subvol="$(echo "$line" | cut -f9 -d' ')"
          echo "Deleting subvolume: $subvol"
          btrfs subvolume delete "/mnt/$subvol" 2>/dev/null || true
        done

        # Delete and recreate root
        if btrfs subvolume delete /mnt/root 2>/dev/null; then
          echo "Creating fresh root subvolume from blank snapshot"
          btrfs subvolume snapshot /mnt/root-blank /mnt/root
        else
          echo "WARNING: Could not delete root subvolume, using existing"
        fi
      ) || {
        echo "WARNING: Rollback failed, continuing with existing root"
      }

      umount /mnt
      exit 0
    '';
  };

  # Create emergency shell accessible without rollback
  systemd.services.emergency-shell = {
    description = "Emergency Shell (bypasses rollback)";
    after = ["rescue.service"];
    unitConfig = {
      DefaultDependencies = false;
    };
    serviceConfig = {
      Type = "idle";
      ExecStart = "${pkgs.bash}/bin/bash";
      StandardInput = "tty";
      StandardOutput = "tty";
      StandardError = "tty";
      TTYPath = "/dev/tty1";
      TTYReset = true;
      TTYVHangup = true;
    };
  };
}
