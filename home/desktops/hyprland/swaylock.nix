{
  config,
  lib,
  pkgs,
  ...
}: {
  config = lib.mkIf (config.desktops.hyprland.enable or false) {
    programs.swaylock = {
      enable = true;

      settings = {
        # Basic settings
        ignore-empty-password = false;
        disable-caps-lock-text = true;
        font = "FiraCode Nerd Font Propo";
        font-size = 24;

        # Use wallpaper as background
        image = "${../../../wallpaper/laptop.jpg}";
        scaling = "fill";

        # Blur effect for Mac-like appearance
        effect-blur = "10x10";
        effect-vignette = "0:1"; # Subtle vignette

        # Indicator settings - Mac-like box style
        indicator = true;
        indicator-radius = 160; # Larger for input box appearance
        indicator-thickness = 4; # Thin border
        indicator-y-position = 700; # Lower on screen (adjust based on your resolution)

        # Show typed characters as dots
        show-failed-attempts = true;

        # Clock display above input
        clock = true;
        timestr = "%I:%M %p";
        datestr = "%A, %B %d";

        # Colors for Mac-like appearance (Tokyo Night with transparency)
        ring-color = lib.mkDefault "7aa2f7aa"; # Semi-transparent blue ring
        ring-ver-color = lib.mkDefault "7dcfffaa"; # Verifying color
        ring-wrong-color = lib.mkDefault "f7768eaa"; # Wrong password color
        ring-clear-color = lib.mkDefault "e0af68aa"; # Clear/backspace color

        key-hl-color = lib.mkDefault "7dcfff"; # Key press highlight
        bs-hl-color = lib.mkDefault "f7768e"; # Backspace highlight

        line-color = lib.mkDefault "00000000"; # Transparent line
        separator-color = lib.mkDefault "00000000"; # Transparent separator

        inside-color = lib.mkDefault "1a1b2688"; # Semi-transparent dark background
        inside-ver-color = lib.mkDefault "1a1b2688";
        inside-wrong-color = lib.mkDefault "1a1b2688";
        inside-clear-color = lib.mkDefault "1a1b2688";

        text-color = lib.mkDefault "c0caf5"; # Light text
        text-ver-color = lib.mkDefault "7dcfff";
        text-wrong-color = lib.mkDefault "f7768e";
        text-clear-color = lib.mkDefault "e0af68";

        # Layout text styling
        layout-bg-color = lib.mkDefault "00000000"; # Transparent background
        layout-border-color = lib.mkDefault "00000000";
        layout-text-color = lib.mkDefault "c0caf5";
      };
    };
  };
}
