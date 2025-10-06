{
  config,
  lib,
  ...
}: let
  # Import our custom lib functions
  moduleLib = import ../../../lib/module {inherit lib;};
  inherit (moduleLib) mkBoolOpt enabled disabled;
in {
  options.modules.home.programs.ssh = {
    enable = mkBoolOpt true "Enable SSH configuration with custom host blocks";
    authorizedKeysAllowed = mkBoolOpt true "Add id_sdev.pub to authorized_keys for SSH access";
  };

  config = lib.mkIf config.modules.home.programs.ssh.enable {
    programs.ssh = {
      enable = true;
      enableDefaultConfig = false;

      matchBlocks = {
        "*" = {
          identityFile = "${config.home.homeDirectory}/.ssh/id_sdev";
        };

        "github.com" = {
          hostname = "ssh.github.com";
          port = 443;
          user = "git";
          identityFile = "${config.home.homeDirectory}/.ssh/id_sdev";
        };

        "siren.nclabs.net" = {
          hostname = "siren.nclabs.net";
          user = "danny";
          identityFile = "${config.home.homeDirectory}/.ssh/id_sdev";
        };
      };
    };

    # Deploy the public key (not sensitive, doesn't need encryption)
    home.file.".ssh/id_sdev.pub".text = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMJKTm63zFmYfGauCBlUWq7lvHFq+NVPT5RqIfjLM7MN danny@solivan.dev";

    # Set up authorized_keys with id_sdev for SSH access
    # Use activation script to copy (not symlink) to avoid SSH permission issues with /nix/store
    home.activation.authorizedKeys = lib.mkIf config.modules.home.programs.ssh.authorizedKeysAllowed (
      lib.hm.dag.entryAfter ["writeBoundary"] ''
        $DRY_RUN_CMD mkdir -p $HOME/.ssh
        $DRY_RUN_CMD chmod 700 $HOME/.ssh
        # Remove symlink if it exists (from previous configurations)
        if [ -L $HOME/.ssh/authorized_keys ]; then
          $DRY_RUN_CMD rm $HOME/.ssh/authorized_keys
        fi
        $DRY_RUN_CMD cat > $HOME/.ssh/authorized_keys <<'EOF'
        # Standard development key for remote access
        ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMJKTm63zFmYfGauCBlUWq7lvHFq+NVPT5RqIfjLM7MN danny@solivan.dev
        EOF
        $DRY_RUN_CMD chmod 600 $HOME/.ssh/authorized_keys
      ''
    );
  };
}
