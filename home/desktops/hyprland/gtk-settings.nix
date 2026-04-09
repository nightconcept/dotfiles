{
  config,
  lib,
  pkgs,
  ...
}: {
  config = lib.mkIf (config.desktops.hyprland.enable or false) {
    # Disable Stylix GTK theming to use proper Tokyo Night GTK theme
    stylix.targets.gtk.enable = lib.mkForce false;

    # GTK 3 Configuration
    gtk.gtk3 = {
      enable = true;

      # Extra GTK3 settings
      extraConfig = {
        gtk-application-prefer-dark-theme = true;
        gtk-button-images = true;
        gtk-enable-animations = true;
        gtk-menu-images = true;
        gtk-modules = "colorreload-gtk-module:appmenu-gtk-module";
        gtk-primary-button-warps-slider = false;
      };
    };

    # GTK 4 Configuration
    gtk.gtk4 = {
      enable = true;
      theme = config.gtk.theme;

      # Extra GTK4 settings
      extraConfig = {
        gtk-application-prefer-dark-theme = true;
        gtk-button-images = true;
        gtk-enable-animations = true;
        gtk-menu-images = true;
        gtk-modules = "colorreload-gtk-module:appmenu-gtk-module";
        gtk-primary-button-warps-slider = false;
        gtk-shell-shows-menubar = 1;
      };
    };

    # General GTK settings (applies to both GTK3 and GTK4)
    gtk = {
      enable = true;

      # Use proper Tokyo Night GTK theme for readable buttons
      theme = lib.mkForce {
        name = "Tokyonight-Dark-B";
        package = pkgs.tokyonight-gtk-theme;
      };

      iconTheme = lib.mkForce {
        name = "Papirus-Dark";
        package = pkgs.papirus-icon-theme;
      };

      # Let Stylix handle cursor and font
      # cursorTheme will be set by Stylix
      # font will be set by Stylix
    };
  };
}
