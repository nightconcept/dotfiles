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
    gaming.enable = true;
    ghostty.enable = true;
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
    nerd-fonts.fira-code
    nerd-fonts.fira-mono
    obsidian
    ungoogled-chromium
    uv
    vlc
    vscode
    xdg-utils
  ];

  desktops.hyprland.enable = true;
}
