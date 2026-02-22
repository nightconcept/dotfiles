{
  config,
  lib,
  pkgs,
  ...
}: let
  moduleLib = import ../../../lib/module {inherit lib;};
  inherit (moduleLib) mkBoolOpt;
in {
  options.modules.home.programs.openclaw = {
    enable = mkBoolOpt false "Enable OpenClaw AI agent (installed via npm global)";
  };

  config = lib.mkIf config.modules.home.programs.openclaw.enable {
    # Ensure npm global prefix and npmrc are set
    home.file.".npmrc".text = lib.mkDefault "prefix=/home/danny/.npm-global\n";

    # Activation script to install/update openclaw via npm global
    home.activation.installOpenClaw = lib.hm.dag.entryAfter ["writeBoundary"] ''
      export PATH="${pkgs.nodejs_22}/bin:$HOME/.npm-global/bin:$PATH"
      if ! command -v openclaw &>/dev/null; then
        $DRY_RUN_CMD ${pkgs.nodejs_22}/bin/npm install -g openclaw@latest 2>/dev/null
      fi
    '';
  };
}
