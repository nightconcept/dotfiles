{
  config,
  lib,
  pkgs,
  ...
}: let
  # nixpkgs removed this package when the unmaintained GTK 2 murrine engine was
  # removed. Build the maintained GTK 3/4 theme directly without propagating
  # that legacy engine.
  tokyonightGtkTheme = pkgs.stdenvNoCC.mkDerivation {
    pname = "tokyonight-gtk-theme";
    version = "0-unstable-2025-10-23";

    src = pkgs.fetchFromGitHub {
      owner = "Fausto-Korpsvart";
      repo = "Tokyonight-GTK-Theme";
      rev = "6c340e058e84c1975a038a8e5d1e384477225dc0";
      hash = "sha256-7H2n9wTaW8Db1RejWK071ITV1j5KIuzfql0Tx9WT6zM=";
    };

    nativeBuildInputs = with pkgs; [
      gnome-shell
      sassc
    ];
    buildInputs = [pkgs.gnome-themes-extra];
    dontBuild = true;

    postPatch = ''
      patchShebangs themes/install.sh
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/share/themes"
      cd themes
      ./install.sh -n Tokyonight -c dark -d "$out/share/themes"
      runHook postInstall
    '';
  };
in {
  config = lib.mkIf (config.desktops.hyprland.enable or false) {
    # Disable Stylix GTK theming to use a complete GTK 3/4 theme with readable widgets.
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

      theme = lib.mkForce {
        name = "Tokyonight-Dark";
        package = tokyonightGtkTheme;
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
