{
  config,
  lib,
  pkgs,
  ...
}: let
  # Import our custom lib functions
  moduleLib = import ../../../lib/module {inherit lib;};
  inherit (moduleLib) mkBoolOpt enabled disabled;
in {
  options.modules.home.programs.spotify = {
    enable = mkBoolOpt false "Enable Spotify music player";
  };

  config = lib.mkIf config.modules.home.programs.spotify.enable {
    home.packages = with pkgs; [
      spotify
    ];
  };
}
