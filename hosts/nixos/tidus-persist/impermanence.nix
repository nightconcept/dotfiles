# Impermanence configuration for tidus
# Defines what persists across reboots
{
  config,
  lib,
  ...
}: {
  # Enable systemd in initrd for rollback service
  boot.initrd.systemd.enable = true;

  # Ensure /persist is available at boot
  fileSystems."/persist".neededForBoot = true;

  # Rollback service to restore root to blank snapshot
  boot.initrd.systemd.services.rollback-root = {
    description = "Rollback BTRFS root subvolume to blank state";
    wantedBy = ["initrd.target"];
    after = ["device-dev-mapper-cryptroot.device"];
    before = ["sysroot.mount"];
    unitConfig.DefaultDependencies = "no";
    serviceConfig.Type = "oneshot";
    script = ''
      mkdir -p /mnt

      # Mount the BTRFS root
      mount -t btrfs -o subvol=/ /dev/mapper/cryptroot /mnt

      # Check if we should skip rollback (for debugging)
      if [ -e /mnt/root/persist-once ]; then
        echo "Found persist-once marker, skipping rollback"
        rm /mnt/root/persist-once
      else
        # Delete all subvolumes under root
        btrfs subvolume list -o /mnt/root |
        while read -r line; do
          subvol="$(echo "$line" | cut -f9 -d' ')"
          echo "Deleting subvolume: $subvol"
          btrfs subvolume delete "/mnt/$subvol"
        done

        # Delete and recreate root
        btrfs subvolume delete /mnt/root
        echo "Creating fresh root subvolume from blank snapshot"
        btrfs subvolume snapshot /mnt/root-blank /mnt/root
      fi

      umount /mnt
    '';
  };

  # Safety: Create marker file to skip rollback once if needed
  environment.shellAliases.persist-once = "sudo touch /persist-once";

  environment.persistence."/persist" = {
    hideMounts = true;

    # System directories that must persist
    directories = [
      # System state
      "/var/log"
      "/var/lib/nixos"
      "/var/lib/systemd"
      "/var/lib/bluetooth"
      "/var/db/sudo/lectured"

      # NetworkManager (WiFi passwords, VPN configs)
      "/etc/NetworkManager/system-connections"
      "/var/lib/NetworkManager"

      # Container runtimes
      {
        directory = "/var/lib/docker";
        user = "root";
        mode = "0700";
      }
      {
        directory = "/var/lib/containers";
        user = "root";
        mode = "0700";
      }

      # Development
      "/var/lib/libvirt"

      # Print system
      "/var/lib/cups"
      "/var/cache/cups"

      # firmware/hardware
      "/var/lib/fprint" # Fingerprint reader
      "/var/lib/tpm" # TPM state

      # Time sync
      "/var/lib/chrony"

      # Package manager caches (optional, for speed)
      "/var/cache/nix"

      # SOPS secrets runtime directory
      "/var/lib/sops-nix"
    ];

    # System files that must persist
    files = [
      "/etc/machine-id"

      # SSH host keys
      "/etc/ssh/ssh_host_rsa_key"
      "/etc/ssh/ssh_host_rsa_key.pub"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"

      # Optional: Persist adjtime for accurate time
      "/etc/adjtime"
    ];

    # User-specific persistence
    users.danny = {
      directories = [
        # User data directories
        "Documents"
        "Downloads"
        "Music"
        "Pictures"
        "Videos"
        "Desktop"
        "Templates"
        "Public"

        # Development
        "git"
        "projects"
        "work"
        ".cargo"
        ".rustup"
        ".npm"
        ".cache/pip"

        # Dotfiles and configs
        {
          directory = ".gnupg";
          mode = "0700";
        }
        {
          directory = ".ssh";
          mode = "0700";
        }
        {
          directory = ".local/share/keyrings";
          mode = "0700";
        }
        ".config/gh" # GitHub CLI
        ".config/sops"

        # Browser profiles
        ".mozilla"
        ".config/google-chrome"
        ".config/chromium"

        # Communication apps
        ".config/discord"
        ".config/Signal"
        ".config/slack"

        # Editors and IDEs
        ".config/Code"
        ".vscode"
        ".config/nvim"

        # Shell and terminal
        ".config/wezterm"
        ".config/zsh"
        ".local/share/zoxide"
        ".local/share/atuin"

        # Desktop environment
        ".config/hypr"
        ".config/waybar"
        ".config/wofi"
        ".config/mako"

        # Media
        ".config/mpv"
        ".config/obs-studio"

        # Gaming (if needed)
        ".local/share/Steam"
        ".config/heroic"

        # Password managers
        ".config/Bitwarden"
        ".config/keepassxc"

        # Nix
        ".cache/nix"
        ".cache/nixpkgs-review"

        # Generic cache and state
        ".cache"
        ".local/state"
        ".local/share"

        # Trash
        ".local/share/Trash"
      ];

      files = [
        # Git config
        ".gitconfig"
        ".gitignore_global"

        # Shell history
        ".zsh_history"
        ".bash_history"

        # Other dotfiles
        ".face"
        ".face.icon"
      ];
    };
  };

  # Ensure /persist exists and has correct permissions
  systemd.tmpfiles.rules = [
    "d /persist 0755 root root -"
    "d /persist/home 0755 root root -"
    "d /persist/home/danny 0755 danny users -"
  ];

  # Needed for our shell alias
  environment.etc."persist-once".text = "";
}
