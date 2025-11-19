# Core Darwin system configuration
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.modules.darwin.core;
in {
  options.modules.darwin.core = {
    enable = mkEnableOption "core Darwin configuration";

    user = mkOption {
      type = types.str;
      default = "danny";
      description = "Primary user for the system";
    };
  };

  config = mkIf cfg.enable {
    # User configuration
    users.users.${cfg.user} = {
      description = "Danny";
      shell = pkgs.zsh;
    };

    # Nix configuration
    nix = {
      optimise.automatic = true;
      settings = {
        allowed-users = [cfg.user];
        trusted-users = ["root" cfg.user "@wheel"];
      };
      gc = {
        automatic = true;
        options = "--delete-older-than 7d";
      };
      extraOptions =
        ''
          experimental-features = nix-command flakes
          keep-outputs = true
          keep-derivations = true
        ''
        + lib.optionalString (pkgs.stdenv.hostPlatform.system == "aarch64-darwin") ''
          extra-platforms = x86_64-darwin aarch64-darwin
        '';
    };

    nixpkgs.config.allowUnfree = true;

    system = {
      primaryUser = cfg.user;
      stateVersion = 4;
    };

    # Core system packages
    environment.systemPackages = with pkgs; [
      bat
      btop
      curl
      gcc
      git
      gnupg
      home-manager
      wget
    ];

    # ZSH configuration
    programs.zsh = {
      enable = true;
      enableCompletion = true;
      enableSyntaxHighlighting = true;
    };

    # Fonts
    fonts.packages = with pkgs; [
      nerd-fonts.fira-code
      nerd-fonts.fira-mono
    ];

    ids.gids.nixbld = 350;
  };
}
