{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [
    ./hyprland.nix
    ./waybar.nix
    ./waybar-lid-handler.nix
    ./wofi-bluetooth.nix
    ./mako.nix
    ./hypridle.nix
    ./hyprlock.nix
    ./wlogout.nix
    ./gtk-settings.nix
    ./dmenu.nix
    ./secrets.nix
  ];

  options.desktops.hyprland = {
    enable = lib.mkEnableOption "Hyprland desktop environment";
  };

  config = lib.mkIf config.desktops.hyprland.enable {
    # Essential packages for Hyprland desktop
    home.packages = with pkgs; [
      # Screenshot tools
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

    # Set default applications for Hyprland (Linux only)
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
      XDG_CURRENT_DESKTOP = "Hyprland";
      XDG_SESSION_TYPE = "wayland";
      XDG_SESSION_DESKTOP = "Hyprland";
    };

    # XDG portal configuration
    xdg.portal = {
      enable = true;
      extraPortals = with pkgs; [
        xdg-desktop-portal-hyprland
        xdg-desktop-portal-gtk
      ];
      config = {
        common = {
          default = [
            "hyprland"
            "gtk"
          ];
        };
      };
    };
  };
}
