{
  config,
  lib,
  pkgs,
  ...
}: let
  moduleLib = import ../../../lib/module {inherit lib;};
  inherit (moduleLib) mkBoolOpt;
in {
  options.modules.home.programs.chrome = {
    enable = mkBoolOpt false "Enable Google Chrome";
  };

  config = lib.mkIf config.modules.home.programs.chrome.enable {
    home.packages = with pkgs; [
      google-chrome
    ];
  };
}
