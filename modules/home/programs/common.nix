{
  config,
  lib,
  pkgs,
  inputs,
  hostname ? "",
  ...
}: let
  # Import our custom lib functions
  moduleLib = import ../../../lib/module {inherit lib;};
  inherit (moduleLib) mkBoolOpt enabled disabled;
  masterPkgs = import inputs.nixpkgs-master {
    system = pkgs.stdenv.hostPlatform.system;
    config.allowUnfree = true;
  };
in {
  options.modules.home.programs.common = {
    enable = mkBoolOpt true "Enable common programs for all systems";
  };

  config = lib.mkIf config.modules.home.programs.common.enable {
    home.packages =
      (with pkgs; [
        alejandra
        bat
        btop
        delta
        duf
        eza
        fastfetch
        fd
        gnupg
        jq
        just
        lazygit
        mosh
        ncdu
        nmap
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
      ++ [masterPkgs.codex]
      # Exclude on rinoa, aerith, and vincent because antigravity-cli 1.0.7 does not build on those hosts.
      ++ lib.optionals (!(builtins.elem hostname ["rinoa" "aerith" "vincent"])) (with pkgs; [
        antigravity-cli
      ]);
  };
}
