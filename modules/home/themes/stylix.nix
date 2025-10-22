{
  config,
  lib,
  pkgs,
  options,
  ...
}: let
  # Import our custom lib functions
  moduleLib = import ../../../lib/module {inherit lib;};
  inherit (moduleLib) mkBoolOpt enabled disabled;

  # Check if stylix option is available (i.e., stylix module is imported)
  stylixAvailable = builtins.hasAttr "stylix" options;
in {
  options.modules.home.themes.stylix = {
    enable = mkBoolOpt false "Enable Stylix theming with Tokyo Night";
  };

  config = lib.mkIf (config.modules.home.themes.stylix.enable && stylixAvailable) {
    stylix = {
      enable = true;

      # Use Tokyo Night theme
      base16Scheme = "${pkgs.base16-schemes}/share/themes/tokyo-night-dark.yaml";

      # Use the laptop wallpaper
      image = ../../../wallpaper/laptop.jpg;

      # Font configuration
      fonts = {
        monospace = {
          package = pkgs.jetbrains-mono;
          name = "JetBrains Mono";
        };
        sansSerif = {
          package = pkgs.noto-fonts;
          name = "Noto Sans";
        };
        serif = {
          package = pkgs.noto-fonts;
          name = "Noto Serif";
        };
        sizes = {
          applications = 11;
          desktop = 10;
          popups = 11;
          terminal = 11;
        };
      };

      # Cursor theme - using default Adwaita
      cursor = {
        package = pkgs.adwaita-icon-theme;
        name = "Adwaita";
        size = 24;
      };

      # Enable styling for applications that need it
      targets = {
        waybar.enable = false;
        wofi.enable = true; # Enable Stylix theming for wofi
        hyprland.enable = false;
        mako.enable = false;
        alacritty.enable = false;
        swaylock.enable = false;
        gtk.enable = true; # Enable GTK theming for dark mode
        gnome.enable = false;
        vscode.enable = false;
        starship.enable = false; # Disable Stylix starship theming (using custom config)
        firefox = {
          enable = true; # Let Stylix handle Firefox theming
          profileNames = ["danny"]; # Specify the profile to theme
        };
        spicetify.enable = true; # Enable Spicetify theming with Tokyo Night colors
        vencord.enable = true; # Enable Vencord Discord theming with Tokyo Night colors
      };

      # Override specific colors if needed
      # You can uncomment and adjust these if you want to tweak the theme
      # override = {
      #   base00 = "1a1b26"; # Default Background
      #   base01 = "16161e"; # Lighter Background
      #   base02 = "2f3549"; # Selection Background
      #   base03 = "444b6a"; # Comments
      #   base04 = "787c99"; # Dark Foreground
      #   base05 = "a9b1d6"; # Default Foreground
      #   base06 = "cbccd1"; # Light Foreground
      #   base07 = "d5d6db"; # Light Background
      #   base08 = "f7768e"; # Red
      #   base09 = "ff9e64"; # Orange
      #   base0A = "e0af68"; # Yellow
      #   base0B = "9ece6a"; # Green
      #   base0C = "73daca"; # Cyan
      #   base0D = "7aa2f7"; # Blue
      #   base0E = "bb9af7"; # Magenta
      #   base0F = "7dcfff"; # Brown
      # };
    };
  };
}
