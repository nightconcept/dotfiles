# Disko configuration for tidus with BTRFS + LUKS + Impermanence
# This creates an encrypted BTRFS filesystem with subvolumes for impermanence
{lib, ...}: {
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        # This will be overridden during install with actual device
        device = lib.mkDefault "/dev/nvme0n1";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              label = "ESP";
              name = "ESP";
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [
                  "defaults"
                  "umask=0077"
                ];
              };
            };
            luks = {
              size = "100%";
              label = "nixos_luks";
              content = {
                type = "luks";
                name = "cryptroot";
                # Warning: This stores the password in the Nix store during install!
                # Use --arg diskPassword for interactive install instead
                askPassword = true;
                settings = {
                  allowDiscards = true;
                  # Optional: Enable FIDO2 support (configure after install)
                  # crypttabExtraOpts = ["fido2-device=auto" "token-timeout=10"];
                };
                extraOpenArgs = [
                  "--allow-discards"
                  "--perf-no_read_workqueue"
                  "--perf-no_write_workqueue"
                ];
                content = {
                  type = "btrfs";
                  extraArgs = ["-f" "-L" "nixos"];
                  subvolumes = {
                    # Root subvolume - gets wiped on every boot
                    "/root" = {
                      mountpoint = "/";
                      mountOptions = ["subvol=root" "compress=zstd" "noatime"];
                    };

                    # Blank root snapshot for rollback
                    "/root-blank" = {
                      mountOptions = ["subvol=root-blank" "compress=zstd" "noatime"];
                    };

                    # Persistent directories
                    "/nix" = {
                      mountpoint = "/nix";
                      mountOptions = ["subvol=nix" "compress=zstd" "noatime"];
                    };

                    "/persist" = {
                      mountpoint = "/persist";
                      mountOptions = ["subvol=persist" "compress=zstd" "noatime"];
                    };

                    "/home" = {
                      mountpoint = "/home";
                      mountOptions = ["subvol=home" "compress=zstd" "noatime"];
                    };

                    # Swap subvolume for hibernation support
                    "/swap" = {
                      mountpoint = "/.swapvol";
                      swap = {
                        swapfile = {
                          size = "16G"; # Match or exceed RAM for hibernation
                        };
                      };
                    };
                  };
                };
              };
            };
          };
        };
      };
    };
  };
}
