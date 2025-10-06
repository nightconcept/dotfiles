{
  config,
  lib,
  ...
}: let
  # Import our custom lib functions
  moduleLib = import ../../../lib/module {inherit lib;};
  inherit (moduleLib) mkBoolOpt enabled disabled;
in {
  options.modules.home.programs.direnv = {
    enable = mkBoolOpt true "Enable direnv for automatic environment loading";
  };

  config = lib.mkIf config.modules.home.programs.direnv.enable {
    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
  };
}
