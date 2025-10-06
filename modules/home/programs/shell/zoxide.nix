{
  config,
  lib,
  pkgs,
  ...
}: let
  # Import our custom lib functions
  moduleLib = import ../../../../lib/module {inherit lib;};
  inherit (moduleLib) mkBoolOpt enabled disabled;
in {
  options.modules.home.programs.shell.zoxide = {
    enable = mkBoolOpt false "Enable Zoxide smart cd";
  };

  config = lib.mkIf config.modules.home.programs.shell.zoxide.enable {
    programs = {
      zoxide = {
        enable = true;
        enableZshIntegration = true;
      };
    };
  };
}
