# Core system packages and fonts
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.modules.nixos.core.packages;
in {
  options.modules.nixos.core.packages = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable core system packages";
    };
  };

  config = mkIf cfg.enable {
    # System packages
    environment.systemPackages = with pkgs; [
      bat
      btop
      cifs-utils
      curl
      gh
      git
      gnupg
      home-manager
      nix-fast-build
      uv
      vim
      wget
      fish
    ];

    # Fonts configuration
    fonts = {
      packages = with pkgs; [
        noto-fonts
        noto-fonts-cjk-sans
        noto-fonts-emoji
        liberation_ttf
        fira-code
        fira-code-symbols
        mplus-outline-fonts.githubRelease
        dina-font
        proggyfonts
        roboto
        ubuntu_font_family
        nerd-fonts.jetbrains-mono
        nerd-fonts.fira-code
        inter
      ];

      enableDefaultPackages = true;

      fontconfig = {
        enable = true;
        defaultFonts = {
          serif = ["Noto Serif"];
          sansSerif = ["Inter"];
          monospace = ["JetBrainsMono Nerd Font"];
        };
      };
    };
  };
}
