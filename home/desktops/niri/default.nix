{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [
    ./niri.nix
    # Reuse components from Hyprland (most are compositor-agnostic)
    ../hyprland/waybar.nix
    ../hyprland/waybar-lid-handler.nix
    ../hyprland/wofi-bluetooth.nix
    ../hyprland/mako.nix
    ../hyprland/hypridle.nix
    ../hyprland/hyprlock.nix
    ../hyprland/wlogout.nix
    ../hyprland/gtk-settings.nix
    ../hyprland/dmenu.nix
    ../hyprland/secrets.nix
  ];

  options.desktops.niri = {
    enable = lib.mkEnableOption "Niri desktop environment";
  };

  config = lib.mkIf config.desktops.niri.enable {
    # Essential packages for Niri desktop
    home.packages = with pkgs; [
      # Screenshot tools (Wayland-compatible)
      grimblast
      grim
      slurp

      # Wallpaper
      swaybg

      # Clipboard
      wl-clipboard
      cliphist

      # Authentication agent
      kdePackages.polkit-kde-agent-1

      # System control
      brightnessctl
      pamixer
      playerctl

      # Notifications and overlays
      libnotify
      wob

      # App launcher dependencies
      dmenu

      # File manager
      thunar

      # Network manager applet
      networkmanagerapplet

      # Font for UI
      nerd-fonts.fira-mono
      nerd-fonts.fira-code
      font-awesome

      # Audio control
      pavucontrol

      # Additional utilities
      hypridle
      hyprlock
      xdg-utils
    ];

    # Set default applications for Niri (Linux only)
    xdg.mimeApps = lib.mkIf pkgs.stdenv.isLinux {
      enable = true;
    };

    # Environment variables for Wayland
    home.sessionVariables = {
      NIXOS_OZONE_WL = "1";
      MOZ_ENABLE_WAYLAND = "1";
      QT_QPA_PLATFORM = "wayland";
      SDL_VIDEODRIVER = "wayland";
      CLUTTER_BACKEND = "wayland";
      XDG_CURRENT_DESKTOP = "niri";
      XDG_SESSION_TYPE = "wayland";
      XDG_SESSION_DESKTOP = "niri";
    };

    # XDG portal configuration
    xdg.portal = {
      enable = true;
      extraPortals = with pkgs; [
        xdg-desktop-portal-gnome
        xdg-desktop-portal-gtk
      ];
      config = {
        common = {
          default = [
            "gtk"
          ];
        };
        niri = {
          default = [
            "gnome"
            "gtk"
          ];
        };
      };
    };
  };
}
