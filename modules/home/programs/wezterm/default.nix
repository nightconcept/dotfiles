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
  options.modules.home.programs.wezterm = {
    enable = mkBoolOpt false "Enable WezTerm terminal emulator";
    configOnly = mkBoolOpt false "Enable WezTerm configuration only (without installing package)";
  };

  config = lib.mkIf (config.modules.home.programs.wezterm.enable || config.modules.home.programs.wezterm.configOnly) {
    programs.wezterm = {
      enable = true;
      # Use dummy package when configOnly mode (manual installation via package manager)
      package = lib.mkIf config.modules.home.programs.wezterm.configOnly (
        pkgs.runCommand "wezterm-dummy" {
          meta.mainProgram = "wezterm";
        } ''
          mkdir -p $out/bin
          touch $out/bin/wezterm
          chmod +x $out/bin/wezterm
        ''
      );
      enableZshIntegration = true;
      extraConfig = builtins.readFile ./config.lua;
    };
  };
}
