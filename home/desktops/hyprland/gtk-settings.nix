{
  config,
  lib,
  pkgs,
  ...
}: {
  config = lib.mkIf (config.desktops.hyprland.enable or false) {
    # GTK 3 Configuration
    gtk.gtk3 = {
      enable = true;

      # Theme, cursor, and font are managed by Stylix now
      # theme = {
      #   name = "cachyos-nord";
      #   package = pkgs.nordic; # Fallback to nordic if cachyos-nord not available
      # };

      # cursorTheme = {
      #   name = "capitaine-cursors";
      #   size = 24;
      #   package = pkgs.capitaine-cursors;
      # };

      # font = {
      #   name = "Fira Sans";
      #   size = 10;
      # };

      # Extra GTK3 settings from CachyOS
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

      # Extra GTK4 settings (has one additional setting)
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

      # Theme, cursor, and font are managed by Stylix now
      # theme = {
      #   name = "cachyos-nord";
      #   package = pkgs.nordic; # Using Nordic as fallback theme
      # };

      iconTheme = {
        name = "Papirus-Dark";
        package = pkgs.papirus-icon-theme;
      };

      # cursorTheme = {
      #   name = "capitaine-cursors";
      #   size = 24;
      #   package = pkgs.capitaine-cursors;
      # };

      # font = {
      #   name = "Fira Sans";
      #   size = 10;
      # };
    };
  };
}
