{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [
    ./wlogout-style.nix
  ];

  config = lib.mkIf (config.desktops.hyprland.enable or false) {
    programs.wlogout = {
      enable = true;

      layout = [
        {
          label = "lock";
          action = "hyprlock";
          text = "Lock";
          keybind = "l";
        }
        {
          label = "hibernate";
          action = "systemctl hibernate";
          text = "Hibernate";
          keybind = "h";
        }
        {
          label = "logout";
          action = "hyprctl dispatch exit";
          text = "Logout";
          keybind = "e";
        }
        {
          label = "shutdown";
          action = "systemctl poweroff";
          text = "Shutdown";
          keybind = "s";
        }
        {
          label = "suspend";
          action = "systemctl suspend";
          text = "Suspend";
          keybind = "u";
        }
        {
          label = "reboot";
          action = "systemctl reboot";
          text = "Reboot";
          keybind = "r";
        }
      ];

      style = let
        colors = config.lib.stylix.colors;
      in ''
        * {
          background-image: none;
          box-shadow: none;
        }

        window {
          background-color: rgba(${colors.base00-rgb-r}, ${colors.base00-rgb-g}, ${colors.base00-rgb-b}, 0.95);
        }

        button {
          border-radius: 8px;
          border-color: #${colors.base03};
          text-decoration-color: #${colors.base05};
          color: #${colors.base05};
          background-color: #${colors.base01};
          border-style: solid;
          border-width: 2px;
          background-repeat: no-repeat;
          background-position: center;
          background-size: 25%;
          margin: 10px;
        }

        button:focus, button:active, button:hover {
          background-color: #${colors.base02};
          border-color: #${colors.base0D};
          outline-style: none;
        }

        #lock {
          background-image: image(url("${pkgs.wlogout}/share/wlogout/icons/lock.png"));
        }

        #logout {
          background-image: image(url("${pkgs.wlogout}/share/wlogout/icons/logout.png"));
        }

        #suspend {
          background-image: image(url("${pkgs.wlogout}/share/wlogout/icons/suspend.png"));
        }

        #hibernate {
          background-image: image(url("${pkgs.wlogout}/share/wlogout/icons/hibernate.png"));
        }

        #shutdown {
          background-image: image(url("${pkgs.wlogout}/share/wlogout/icons/shutdown.png"));
        }

        #reboot {
          background-image: image(url("${pkgs.wlogout}/share/wlogout/icons/reboot.png"));
        }
      '';
    };
  };
}
