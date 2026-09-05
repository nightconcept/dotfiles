{
  config,
  lib,
  pkgs,
  ...
}: let
  moduleLib = import ../../../lib/module {inherit lib;};
  inherit (moduleLib) mkBoolOpt;
  miseBin = pkgs.callPackage ../../../pkgs/mise/package.nix {};
in {
  options.modules.home.programs.mise = {
    enable = mkBoolOpt false "Enable mise for managing language runtimes and tools";
  };

  config.programs.mise = lib.mkIf config.modules.home.programs.mise.enable {
    enable = true;
    package = miseBin;
  };
}
