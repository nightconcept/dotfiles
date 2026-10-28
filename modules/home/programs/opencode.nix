{
  config,
  lib,
  pkgs,
  ...
}: let
  moduleLib = import ../../../lib/module {inherit lib;};
  inherit (moduleLib) mkBoolOpt;
in {
  options.modules.home.programs.opencode = {
    enable = mkBoolOpt false "Enable the opencode coding agent CLI";
  };

  config = lib.mkIf config.modules.home.programs.opencode.enable {
    home.packages = [pkgs.opencode];
  };
}
