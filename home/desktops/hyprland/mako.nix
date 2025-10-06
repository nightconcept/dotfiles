{
  config,
  lib,
  pkgs,
  ...
}: {
  config = lib.mkIf (config.desktops.hyprland.enable or false) {
    services.mako = {
      enable = true;

      settings = {
        # Display settings
        max-visible = 10;
        layer = "top";
        anchor = "top-right";
        margin = 20;

        # Font configuration
        font = "Sarasa UI SC 10";

        # Colors - Tokyo Night theme (can be overridden by Stylix)
        background-color = lib.mkDefault "#1a1b26dd";
        text-color = lib.mkDefault "#c0caf5";
        border-color = lib.mkDefault "#3b4261";

        # Appearance
        border-radius = 7;
        max-icon-size = 48;

        # Timeout
        default-timeout = 10000;
      };
    };
  };
}
