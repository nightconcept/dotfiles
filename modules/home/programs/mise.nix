{
  config,
  lib,
  ...
}: let
  moduleLib = import ../../../lib/module {inherit lib;};
  inherit (moduleLib) mkBoolOpt;
in {
  options.modules.home.programs.mise = {
    enable = mkBoolOpt false "Enable mise for managing language runtimes and tools";
  };

  config = lib.mkIf config.modules.home.programs.mise.enable {
    programs.mise = {
      enable = true;
    };
  };
}
