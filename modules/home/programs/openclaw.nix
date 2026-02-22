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
    # Build deps for `npm install -g --prefix ~/.npm-global openclaw`
    # Run manually once per machine — not automated because openclaw
    # has native C++ deps (@discordjs/opus) that need a full toolchain.
    home.packages = with pkgs; [
      python3
      gcc
      gnumake
      pkg-config
      libopus
    ];
  };
}
