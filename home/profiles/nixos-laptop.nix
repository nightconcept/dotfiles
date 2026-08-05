# Desktop configuration for GUI environments
{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [
    ./base.nix
    ../../modules/home
    ../desktops/hyprland
  ];

  modules.home.programs = {
    chromium.enable = true;
    dev-languages.enable = true;
    dev-tools.enable = true;
    gaming.enable = true;
    ghostty.enable = true;
    herdr.enable = true;
    rofi.enable = true;
    spotify.enable = true;
    zotero.enable = true;
    # wezterm.enable = true; # Replaced by ghostty
    xdg.enable = true;
    shell = {
      fish.enable = true;
      starship.enable = true;
      zoxide.enable = true;
    };
  };

  modules.home.themes.stylix.enable = true;

  fonts.fontconfig.enable = true;

  home.packages = with pkgs; [
    firefox
    github-desktop
    kdePackages.xdg-desktop-portal-kde
    librewolf
    nerd-fonts.fira-code
    nerd-fonts.fira-mono
    obsidian
    vlc
    vscode
    xdg-utils
  ];

  desktops.hyprland.enable = true;
}
