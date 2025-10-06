{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [
  ];

  config = lib.mkIf (config.desktops.hyprland.enable or false) {
    programs.wofi = {
      enable = true;

      settings = {
        allow_images = true;
        hide_scroll = true;
        no_actions = false;
        term = "alacritty";
        mode = "drun";
      };

      style = let
        colors = config.lib.stylix.colors;
      in ''
        * {
          font-family: "${config.stylix.fonts.monospace.name}", monospace;
          font-size: ${toString config.stylix.fonts.sizes.applications}px;
        }

        window {
          background-color: rgba(${colors.base00-rgb-r}, ${colors.base00-rgb-g}, ${colors.base00-rgb-b}, 0.95);
          border: 2px solid #${colors.base0D};
          border-radius: 8px;
        }

        #input {
          margin: 5px;
          border-radius: 4px;
          border: 1px solid #${colors.base03};
          background-color: #${colors.base01};
          color: #${colors.base05};
          padding: 8px;
        }

        #inner-box {
          background-color: transparent;
        }

        #outer-box {
          margin: 2px;
          padding: 10px;
          background-color: transparent;
        }

        #scroll {
          margin: 5px;
        }

        #text {
          padding: 4px;
          color: #${colors.base05};
        }

        #entry {
          margin: 2px;
          padding: 6px;
          border-radius: 4px;
        }

        #entry:nth-child(even){
          background-color: #${colors.base01};
        }

        #entry:selected {
          background-color: #${colors.base02};
          border: 1px solid #${colors.base0D};
        }

        #text:selected {
          color: #${colors.base05};
          font-weight: bold;
        }
      '';
    };
  };
}
