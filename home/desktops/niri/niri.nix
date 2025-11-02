{
  config,
  lib,
  pkgs,
  ...
}: {
  config = lib.mkIf (config.desktops.niri.enable or false) {
    programs.niri = {
      enable = true;

      settings = {
        # Input configuration
        input = {
          keyboard = {
            xkb = {
              layout = "us";
            };
          };

          touchpad = {
            tap = true;
            natural-scroll = true;
            dwt = true;
            dwtp = true;
            # Disable middle-click emulation to match Hyprland config
            click-method = "clickfinger";
          };

          mouse = {
            # Natural scrolling for mouse to match touchpad
            natural-scroll = false;
          };

          focus-follows-mouse = {
            enable = true;
            # Match Hyprland's follow_mouse = 2 behavior
            max-scroll-amount = "5%";
          };
        };

        # Output configuration
        outputs = {
          "eDP-1" = {
            # Default monitor configuration
            mode = {
              width = 1920;
              height = 1080;
              refresh = 60.0;
            };
            scale = 1.0;
          };
        };

        # Layout configuration (scrollable-tiling is niri's default)
        layout = {
          gaps = 6; # Match Hyprland's gaps_out
          center-focused-column = "on-overflow";
          preset-column-widths = [
            {proportion = 0.33333;}
            {proportion = 0.5;}
            {proportion = 0.66667;}
          ];
          default-column-width = {proportion = 0.5;};
        };

        # Window rules
        window-rules = [
          # Float necessary windows
          {
            matches = [
              {app-id = "^org\\.pulseaudio\\.pavucontrol$";}
              {app-id = "^blueman-manager$";}
              {app-id = "^zenity$";}
            ];
            open-floating = true;
          }

          # Opacity rules
          {
            matches = [{app-id = "^(thunar|nemo)$";}];
            opacity = 0.92;
          }
          {
            matches = [{app-id = "^(discord|armcord|webcord)$";}];
            opacity = 0.96;
          }
        ];

        # Border configuration
        border = {
          enable = true;
          width = 3;
          # Using Tokyo Night colors (approximation)
          active.color = "#7aa2f7"; # tokyonight_blue
          inactive.color = "#292e42"; # tokyonight_bg_highlight
        };

        # Prefer no server-side decorations
        prefer-no-csd = true;

        # Screenshot command
        screenshot-path = "~/Pictures/Screenshots/screenshot-%Y-%m-%d-%H-%M-%S.png";

        # Cursor configuration
        cursor = {
          size = 24;
        };

        # Spawn at startup
        spawn-at-startup = [
          {command = ["swaybg" "-o" "*" "-i" "${../../wallpaper/laptop.jpg}" "-m" "fill"];}
          {command = ["mako"];}
          {command = ["nm-applet" "--indicator"];}
          {command = ["${pkgs.kdePackages.polkit-kde-agent-1}/libexec/polkit-kde-authentication-agent-1"];}
          {command = ["hypridle-wrapper"];}
        ];

        # Keybindings
        binds = with config.lib.niri.actions; let
          # Helper to spawn commands
          sh = spawn "sh" "-c";
        in {
          # Main keybinds
          "Mod+Return".action = spawn "ghostty";
          "Mod+T".action = spawn "thunar";
          "Mod+B".action = spawn "firefox";
          "Mod+Shift+B".action = spawn "wofi-bluetooth";
          "Mod+Q".action = close-window;
          "Mod+E".action = spawn "code";
          "Mod+Space".action = spawn "rofi" "-show" "drun";

          # Floating window toggle (not directly supported in niri, using fullscreen as alternative)
          "Mod+F".action = fullscreen-window;

          # Screenshots using grim/slurp
          "Print".action = sh "grimblast copy area";
          "Ctrl+Print".action = sh "grimblast copy active";
          "Alt+Print".action = sh "grimblast copy output";

          # Lock screen
          "Mod+L".action = spawn "hyprlock";

          # Power menu
          "Mod+BackSpace".action = spawn "wlogout";

          # Window focus (vim-style navigation)
          "Mod+H".action = focus-column-left;
          "Mod+J".action = focus-window-down;
          "Mod+K".action = focus-window-up;
          "Mod+Semicolon".action = focus-column-right;

          # Window movement
          "Mod+Shift+H".action = move-column-left;
          "Mod+Shift+J".action = move-window-down;
          "Mod+Shift+K".action = move-window-up;
          "Mod+Shift+Semicolon".action = move-column-right;

          # Workspace switching (niri uses scrollable workspaces)
          "Mod+1".action = focus-workspace 1;
          "Mod+2".action = focus-workspace 2;
          "Mod+3".action = focus-workspace 3;
          "Mod+4".action = focus-workspace 4;
          "Mod+5".action = focus-workspace 5;
          "Mod+6".action = focus-workspace 6;
          "Mod+7".action = focus-workspace 7;
          "Mod+8".action = focus-workspace 8;
          "Mod+9".action = focus-workspace 9;
          "Mod+0".action = focus-workspace 10;

          # Move to workspace
          "Mod+Shift+1".action = move-column-to-workspace 1;
          "Mod+Shift+2".action = move-column-to-workspace 2;
          "Mod+Shift+3".action = move-column-to-workspace 3;
          "Mod+Shift+4".action = move-column-to-workspace 4;
          "Mod+Shift+5".action = move-column-to-workspace 5;
          "Mod+Shift+6".action = move-column-to-workspace 6;
          "Mod+Shift+7".action = move-column-to-workspace 7;
          "Mod+Shift+8".action = move-column-to-workspace 8;
          "Mod+Shift+9".action = move-column-to-workspace 9;
          "Mod+Shift+0".action = move-column-to-workspace 10;

          # Workspace navigation (left/right)
          "Mod+Period".action = focus-workspace-down;
          "Mod+Comma".action = focus-workspace-up;

          # Column width adjustments (niri's unique feature)
          "Mod+R".action = switch-preset-column-width;
          "Mod+Shift+R".action = reset-window-height;
          "Mod+Minus".action = set-column-width "-10%";
          "Mod+Equal".action = set-column-width "+10%";

          # Window resizing
          "Mod+Alt+H".action = set-column-width "-10%";
          "Mod+Alt+J".action = set-window-height "+10%";
          "Mod+Alt+K".action = set-window-height "-10%";
          "Mod+Alt+Semicolon".action = set-column-width "+10%";

          # Volume control
          "XF86AudioRaiseVolume".action = sh "wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+ && pkill -RTMIN+8 waybar";
          "XF86AudioLowerVolume".action = sh "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- && pkill -RTMIN+8 waybar";
          "XF86AudioMute".action = sh "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle && pkill -RTMIN+8 waybar";
          "F3".action = sh "wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+ && pkill -RTMIN+8 waybar";
          "F2".action = sh "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- && pkill -RTMIN+8 waybar";
          "F1".action = sh "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle && pkill -RTMIN+8 waybar";
          "F4".action = sh "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle && pkill -RTMIN+8 waybar";

          # Brightness control
          "XF86MonBrightnessUp".action = sh "brightnessctl s +5%";
          "XF86MonBrightnessDown".action = sh "brightnessctl s 5%-";
          "F7".action = sh "brightnessctl s +5%";
          "F6".action = sh "brightnessctl s 5%-";

          # Media control
          "XF86AudioPlay".action = sh "playerctl play-pause";
          "XF86AudioNext".action = sh "playerctl next";
          "XF86AudioPrev".action = sh "playerctl previous";

          # Niri-specific actions
          "Mod+Shift+E".action = quit;
          "Mod+Shift+P".action = power-off-monitors;

          # Consume or expel window from column
          "Mod+BracketLeft".action = consume-window-into-column;
          "Mod+BracketRight".action = expel-window-from-column;

          # Center column on screen
          "Mod+C".action = center-column;

          # Switch focus between windows
          "Mod+Tab".action = focus-window-down-or-column-right;
          "Mod+Shift+Tab".action = focus-window-up-or-column-left;
        };

        # Animation settings
        animations = {
          slowdown = 1.0;
          window-open = {
            duration-ms = 150;
            curve = "ease-out-cubic";
          };
          window-close = {
            duration-ms = 150;
            curve = "ease-out-cubic";
          };
          window-movement = {
            duration-ms = 200;
            curve = "ease-out-cubic";
          };
          workspace-switch = {
            duration-ms = 250;
            curve = "ease-out-cubic";
          };
        };

        # Debug options (can be disabled in production)
        debug = {
          render-drm-device = null;
        };
      };
    };
  };
}
