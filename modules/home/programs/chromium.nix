{
  config,
  lib,
  pkgs,
  ...
}: let
  moduleLib = import ../../../lib/module {inherit lib;};
  inherit (moduleLib) mkBoolOpt;
in {
  options.modules.home.programs.chromium = {
    enable = mkBoolOpt false "Enable Chromium";
  };

  config = lib.mkIf config.modules.home.programs.chromium.enable {
    home.packages = with pkgs; [
      ungoogled-chromium
    ];
  };
}
