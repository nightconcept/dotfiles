{
  config,
  lib,
  pkgs,
  ...
}: {
  config = lib.mkIf (config.desktops.hyprland.enable or false) {
    # Dmenu configuration from CachyOS
    home.file.".dmenurc" = {
      text = ''
        #
        # ~/.dmenurc
        #

        ## define the font for dmenu to be used
        DMENU_FN="Noto-10.5"

        ## command for the terminal application to be used:
        TERMINAL_CMD="terminal -e"

        ## export our variables
        DMENU_OPTIONS="-fn $DMENU_FN"
      '';
    };

    # Also set environment variable for dmenu
    home.sessionVariables = {
      DMENU_OPTIONS = "-fn Noto-10.5";
    };
  };
}
