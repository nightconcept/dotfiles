{
  config,
  lib,
  pkgs,
  ...
}: {
  options.modules.home.programs.rofi = {
    enable = lib.mkEnableOption "rofi application launcher";
  };

  config = lib.mkIf config.modules.home.programs.rofi.enable {
    # Disable stylix rofi theming to avoid conflicts
    stylix.targets.rofi.enable = false;

    programs.rofi = {
      enable = true;
      package = pkgs.rofi;

      theme = let
        inherit (config.lib.formats.rasi) mkLiteral;
      in {
        "*" = {
          # Tokyo Night color palette
          bg-col = mkLiteral "#1a1b26"; # tokyonight_bg
          bg-col-light = mkLiteral "#292e42"; # tokyonight_bg_highlight
          border-col = mkLiteral "#7aa2f7"; # tokyonight_blue
          selected-col = mkLiteral "#3b4261"; # tokyonight_fg_gutter
          blue = mkLiteral "#7aa2f7"; # tokyonight_blue
          cyan = mkLiteral "#7dcfff"; # tokyonight_cyan
          fg-col = mkLiteral "#c0caf5"; # tokyonight_fg
          fg-col2 = mkLiteral "#a9b1d6"; # tokyonight_fg_dark
          grey = mkLiteral "#565f89"; # tokyonight_comment
          red = mkLiteral "#f7768e"; # tokyonight_red
          green = mkLiteral "#9ece6a"; # tokyonight_green
          yellow = mkLiteral "#e0af68"; # tokyonight_yellow
          orange = mkLiteral "#ff9e64"; # tokyonight_orange
          purple = mkLiteral "#bb9af7"; # tokyonight_magenta

          width = 600;
          font = "${config.stylix.fonts.monospace.name} ${toString config.stylix.fonts.sizes.applications}";
        };

        "element-text, element-icon, mode-switcher" = {
          background-color = mkLiteral "inherit";
          text-color = mkLiteral "inherit";
        };

        "window" = {
          height = mkLiteral "360px";
          border = mkLiteral "3px";
          border-color = mkLiteral "@border-col";
          background-color = mkLiteral "@bg-col";
          border-radius = mkLiteral "8px";
        };

        "mainbox" = {
          background-color = mkLiteral "@bg-col";
        };

        "inputbar" = {
          children = map mkLiteral ["prompt" "entry"];
          background-color = mkLiteral "@bg-col";
          border-radius = mkLiteral "5px";
          padding = mkLiteral "2px";
        };

        "prompt" = {
          background-color = mkLiteral "@cyan";
          padding = mkLiteral "6px";
          text-color = mkLiteral "@bg-col";
          border-radius = mkLiteral "3px";
          margin = mkLiteral "20px 0px 0px 20px";
        };

        "textbox-prompt-colon" = {
          expand = false;
          str = ":";
        };

        "entry" = {
          padding = mkLiteral "6px";
          margin = mkLiteral "20px 0px 0px 10px";
          text-color = mkLiteral "@fg-col";
          background-color = mkLiteral "@bg-col";
        };

        "listview" = {
          border = mkLiteral "0px 0px 0px";
          padding = mkLiteral "6px 0px 0px";
          margin = mkLiteral "10px 0px 0px 20px";
          columns = 2;
          lines = 5;
          background-color = mkLiteral "@bg-col";
        };

        "element" = {
          padding = mkLiteral "5px";
          background-color = mkLiteral "@bg-col";
          text-color = mkLiteral "@fg-col";
        };

        "element-icon" = {
          size = mkLiteral "25px";
        };

        "element selected" = {
          background-color = mkLiteral "@selected-col";
          border = mkLiteral "0px 0px 0px 2px";
          border-color = mkLiteral "@cyan";
          text-color = mkLiteral "@cyan";
        };

        "mode-switcher" = {
          spacing = 0;
        };

        "button" = {
          padding = mkLiteral "10px";
          background-color = mkLiteral "@bg-col-light";
          text-color = mkLiteral "@grey";
          vertical-align = mkLiteral "0.5";
          horizontal-align = mkLiteral "0.5";
        };

        "button selected" = {
          background-color = mkLiteral "@bg-col";
          text-color = mkLiteral "@cyan";
        };

        "message" = {
          background-color = mkLiteral "@bg-col-light";
          margin = mkLiteral "2px";
          padding = mkLiteral "2px";
          border-radius = mkLiteral "5px";
        };

        "textbox" = {
          padding = mkLiteral "6px";
          margin = mkLiteral "20px 0px 0px 20px";
          text-color = mkLiteral "@cyan";
          background-color = mkLiteral "@bg-col-light";
        };
      };
    };
  };
}
