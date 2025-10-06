# Impermanence configuration module
# NOTE: This module requires the impermanence flake input to be added to flake.nix
# and imported in the system configuration. Currently not in use.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.modules.nixos.storage.impermanence;
in {
  options.modules.nixos.storage.impermanence = {
    enable = mkEnableOption "Impermanence (ephemeral root) - requires impermanence flake input";
  };

  config = mkIf cfg.enable {
    # NOTE: This configuration requires:
    # 1. Add impermanence to flake inputs:
    #    impermanence.url = "github:nix-community/impermanence";
    # 2. Import the module in your system configuration:
    #    inputs.impermanence.nixosModules.impermanence
    # 3. Configure the persistence as shown below

    assertions = [
      {
        assertion = false;
        message = ''
          The impermanence module is not currently configured.
          To use impermanence, you need to:
          1. Add impermanence to your flake inputs
          2. Import inputs.impermanence.nixosModules.impermanence in your system
          3. Enable this module
        '';
      }
    ];

    # Original impermanence configuration (commented out until properly set up)
    # boot.initrd.postDeviceCommands = mkAfter ''
    #   mkdir /btrfs_tmp
    #   mount /dev/root_vg/root /btrfs_tmp
    #   if [[ -e /btrfs_tmp/root ]]; then
    #       mkdir -p /btrfs_tmp/old_roots
    #       timestamp=$(date --date="@$(stat -c %Y /btrfs_tmp/root)" "+%Y-%m-%-d_%H:%M:%S")
    #       mv /btrfs_tmp/root "/btrfs_tmp/old_roots/$timestamp"
    #   fi
    #
    #   delete_subvolume_recursively() {
    #       IFS=$'\n'
    #       for i in $(btrfs subvolume list -o "$1" | cut -f 9- -d ' '); do
    #           delete_subvolume_recursively "/btrfs_tmp/$i"
    #       done
    #       btrfs subvolume delete "$1"
    #   }
    #
    #   for i in $(find /btrfs_tmp/old_roots/ -maxdepth 1 -mtime +30); do
    #       delete_subvolume_recursively "$i"
    #   done
    #
    #   btrfs subvolume create /btrfs_tmp/root
    #   umount /btrfs_tmp
    # '';
  };
}
