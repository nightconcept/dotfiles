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
  options.modules.home.programs.gaming = {
    enable = mkBoolOpt false "Enable gaming-related packages and tools";
  };

  config = lib.mkIf config.modules.home.programs.gaming.enable {
    home.packages = with pkgs; [
      #lact
      protonup-qt
    ];
  };
}
