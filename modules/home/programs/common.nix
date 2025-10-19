{
  config,
  lib,
  pkgs,
  ...
}: let
  # Import our custom lib functions
  moduleLib = import ../../../lib/module {inherit lib;};
  inherit (moduleLib) mkBoolOpt enabled disabled;
in {
  options.modules.home.programs.common = {
    enable = mkBoolOpt true "Enable common programs for all systems";
  };

  config = lib.mkIf config.modules.home.programs.common.enable {
    home.packages = with pkgs; [
      alejandra
      any-nix-shell
      bat
      btop
      claude-code
      codex
      delta
      desktop-file-utils
      devenv
      duf
      eza
      fastfetch
      gnupg
      jq
      just
      lazygit
      lua51Packages.lua
      ncdu
      nix-prefetch-github
      nmap
      nodejs_22
      rsync
      uv
      vim
      wget
      zip
      zoxide
    ];
  };
}
