{
  config,
  lib,
  pkgs,
  ...
}: let
  # Import our custom lib functions
  moduleLib = import ../../../../lib/module {inherit lib;};
  inherit (moduleLib) mkBoolOpt enabled disabled;
in {
  options.modules.home.programs.shell.starship = {
    enable = mkBoolOpt false "Enable Starship prompt";
  };

  config = lib.mkIf config.modules.home.programs.shell.starship.enable {
    programs.starship = {
      enable = true;
      # Use external TOML configuration file from shared directory
      # This allows the same config to be used across Nix, non-Nix, and Windows systems
      settings = builtins.fromTOML (builtins.readFile ../../../../shared/starship.toml);
    };
  };
}
