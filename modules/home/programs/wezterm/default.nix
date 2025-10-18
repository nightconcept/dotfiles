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
      package = lib.mkIf config.modules.home.programs.wezterm.configOnly (pkgs.runCommand "empty-directory" {} "mkdir $out");
      enableZshIntegration = true;
      extraConfig = builtins.readFile ./config.lua;
    };
  };
}
