{
  config,
  lib,
  pkgs,
  hostname ? "",
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
    home.packages =
      (with pkgs; [
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
        fd
        gnupg
        jq
        just
        lazygit
        lua51Packages.lua
        ncdu
        nix-prefetch-github
        nixpkgs-review
        nmap
        nodejs_24
        opencode
        ripgrep
        rsync
        sops
        uv
        vim
        wget
        zip
        zoxide
      ])
      # Exclude on rinoa, aerith, and vincent because antigravity-cli 1.0.7 does not build on those hosts.
      ++ lib.optionals (!(builtins.elem hostname ["rinoa" "aerith" "vincent"])) (with pkgs; [
        antigravity-cli
      ]);
  };
}
