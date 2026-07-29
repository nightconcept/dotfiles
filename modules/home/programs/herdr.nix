{
  config,
  lib,
  pkgs,
  ...
}: let
  moduleLib = import ../../../lib/module {inherit lib;};
  inherit (moduleLib) mkBoolOpt;
in {
  options.modules.home.programs.herdr = {
    enable = mkBoolOpt false "Enable Herdr AI agent multiplexer";
  };

  config = lib.mkIf config.modules.home.programs.herdr.enable {
    home.packages = [pkgs.herdr];

    xdg.configFile."herdr/config.toml".text = ''
      # Herdr configuration
      # https://herdr.dev/docs/configuration/

      [theme]
      name = "tokyo-night"

      [keys]
      # prefix is ctrl+b by default — set explicitly for clarity
      prefix = "ctrl+b"
    '';
  };
}
