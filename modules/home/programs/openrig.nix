{
  config,
  lib,
  pkgs,
  ...
}: let
  moduleLib = import ../../../lib/module {inherit lib;};
  inherit (moduleLib) mkBoolOpt;
  openrig = pkgs.callPackage ../../../pkgs/openrig/package.nix {};
in {
  options.modules.home.programs.openrig = {
    enable = mkBoolOpt false "Enable OpenRig (rig CLI) for running persistent agent teams";
  };

  config = lib.mkIf config.modules.home.programs.openrig.enable {
    home.packages = [openrig];
  };
}
