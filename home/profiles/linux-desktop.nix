# Linux (non-NixOS) Desktops
{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [
    ./base.nix
    ../../modules/home
  ];

  # Configure nixGL for OpenGL support on non-NixOS systems
  nixGL.defaultWrapper = "mesa"; # Use mesa wrapper for Intel/AMD/Nouveau
  nixGL.installScripts = ["mesa"]; # Install mesa wrapper scripts

  # Wrap ghostty with nixGL for OpenGL support
  programs.ghostty.package = config.lib.nixGL.wrap pkgs.ghostty;

  modules.home.programs = {
    ghostty.enable = true;
    spotify.enable = true;
    # wezterm.configOnly = true; # Replaced by ghostty
    xdg.enable = true;
    shell = {
      fish.enable = true;
      starship.enable = true;
      zoxide.enable = true;
    };
  };

  fonts.fontconfig.enable = true;

  home.packages = with pkgs; [
    github-desktop
    gitnuro
    kdePackages.xdg-desktop-portal-kde
    nerd-fonts.fira-code
    nerd-fonts.fira-mono
    obsidian
    uv
    vlc
    vscode
    xdg-utils
  ];

  stylix.targets.gtk.enable = lib.mkForce false;
}
