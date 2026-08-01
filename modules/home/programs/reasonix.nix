{
  config,
  lib,
  pkgs,
  ...
}: let
  moduleLib = import ../../../lib/module {inherit lib;};
  inherit (moduleLib) mkBoolOpt;
in {
  options.modules.home.programs.reasonix = {
    enable = mkBoolOpt false "Enable the reasonix (deepseek-reasonix) coding agent CLI";
  };

  config = lib.mkIf config.modules.home.programs.reasonix.enable {
    home.packages = [
      (pkgs.callPackage ../../../pkgs/reasonix/package.nix {})
    ];
  };
}
