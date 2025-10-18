{
  config,
  lib,
  pkgs,
  ...
}: {
  config = lib.mkIf (config.desktops.hyprland.enable or false) {
    wayland.windowManager.hyprland = {
      enable = true;
      xwayland.enable = true;

      settings = {
        # Main modifier key
        "$mod" = "SUPER";

        # Default applications
        "$terminal" = "ghostty";
        "$filemanager" = "";
        "$applauncher" = "rofi -show drun";
        "$browser" = "firefox";
        "$idlehandler" = "hypridle";

        # Screenshot commands
        "$shot-region" = "grimblast copy area";
        "$shot-window" = "grimblast copy active";
        "$shot-screen" = "grimblast copy output";

        # Tokyo Night color definitions
        "$tokyonight_bg" = "rgba(1a1b26ff)";
        "$tokyonight_bg_dark" = "rgba(16161eff)";
        "$tokyonight_bg_highlight" = "rgba(292e42ff)";
        "$tokyonight_terminal_black" = "rgba(414868ff)";
        "$tokyonight_fg" = "rgba(c0caf5ff)";
        "$tokyonight_fg_dark" = "rgba(a9b1d6ff)";
        "$tokyonight_fg_gutter" = "rgba(3b4261ff)";
        "$tokyonight_dark3" = "rgba(545c7eff)";
        "$tokyonight_comment" = "rgba(565f89ff)";
        "$tokyonight_dark5" = "rgba(737aa2ff)";
        "$tokyonight_blue0" = "rgba(3d59a1ff)";
        "$tokyonight_blue" = "rgba(7aa2f7ff)";
        "$tokyonight_cyan" = "rgba(7dcfffff)";
        "$tokyonight_blue1" = "rgba(2ac3deff)";
        "$tokyonight_blue2" = "rgba(0db9d7ff)";
        "$tokyonight_blue5" = "rgba(89ddffff)";
        "$tokyonight_blue6" = "rgba(b4f9f8ff)";
        "$tokyonight_blue7" = "rgba(394b70ff)";
        "$tokyonight_magenta" = "rgba(bb9af7ff)";
        "$tokyonight_magenta2" = "rgba(ff007cff)";
        "$tokyonight_purple" = "rgba(9d7cd8ff)";
        "$tokyonight_orange" = "rgba(ff9e64ff)";
        "$tokyonight_yellow" = "rgba(e0af68ff)";
        "$tokyonight_green" = "rgba(9ece6aff)";
        "$tokyonight_green1" = "rgba(73dacaff)";
        "$tokyonight_green2" = "rgba(41a6b5ff)";
        "$tokyonight_teal" = "rgba(1abc9cff)";
        "$tokyonight_red" = "rgba(f7768eff)";
        "$tokyonight_red1" = "rgba(db4b4bff)";

        # Monitor configuration (can be customized per-host)
        monitor = ",preferred,auto,1";

        # Environment variables
        env = [
          "HYPRCURSOR_SIZE,24"
          "XCURSOR_SIZE,24"
          "QT_CURSOR_SIZE,24"
          "ELECTRON_OZONE_PLATFORM_HINT,auto"
        ];

        # Input configuration (updated from CachyOS)
        input = {
          kb_layout = "us";
          follow_mouse = 2; # Updated from CachyOS
          float_switch_override_focus = 2; # Added from CachyOS
          touchpad = {
            natural_scroll = true;
            middle_button_emulation = false; # Disable middle-click emulation
            tap-to-click = true;
            clickfinger_behavior = false; # Disable multi-finger click behaviors
          };
          sensitivity = 0;
        };

        # General configuration
        general = {
          gaps_in = 3;
          gaps_out = 6;
          border_size = 3;
          "col.active_border" = "$tokyonight_blue $tokyonight_cyan 45deg";
          "col.inactive_border" = "$tokyonight_bg_highlight";
          layout = "dwindle";
          snap = {
            enabled = true;
          };
        };

        # Decoration configuration
        decoration = {
          active_opacity = 1.0;
          rounding = 4;
          blur = {
            size = 15;
            passes = 2;
            xray = true;
          };
          shadow = {
            enabled = false;
          };
        };

        # Animation configuration
        animations = {
          enabled = true;
          bezier = "overshot, 0.13, 0.99, 0.29, 1.1";
          animation = [
            "windowsIn, 1, 4, overshot, slide"
            "windowsOut, 1, 5, default, popin 80%"
            "border, 1, 5, default"
            "workspacesIn, 1, 6, overshot, slide"
            "workspacesOut, 1, 6, overshot, slidefade 80%"
          ];
        };

        # Dwindle layout configuration
        dwindle = {
          special_scale_factor = 0.8;
          pseudotile = true;
          preserve_split = true;
        };

        # Master layout configuration
        master = {
          new_status = "master";
          special_scale_factor = 0.8;
        };

        # Group configuration
        group = {
          "col.border_active" = "$tokyonight_blue";
          "col.border_inactive" = "$tokyonight_dark3";
          "col.border_locked_active" = "$tokyonight_magenta";
          "col.border_locked_inactive" = "$tokyonight_dark5";
          groupbar = {
            font_family = "Fira Sans";
            text_color = "$tokyonight_fg";
            "col.active" = "$tokyonight_blue";
            "col.inactive" = "$tokyonight_dark3";
            "col.locked_active" = "$tokyonight_magenta";
            "col.locked_inactive" = "$tokyonight_dark5";
          };
        };

        # Misc configuration
        misc = {
          font_family = "Fira Sans";
          splash_font_family = "Fira Sans";
          disable_hyprland_logo = true;
          "col.splash" = "$tokyonight_blue";
          background_color = "$tokyonight_bg";
          enable_swallow = true;
          swallow_regex = "^(cachy-browser|firefox|nautilus|nemo|thunar|btrfs-assistant.)$";
          focus_on_activate = true;
          vrr = 2;
        };

        # Render configuration
        render = {
          direct_scanout = true;
        };

        # Binds configuration
        binds = {
          allow_workspace_cycles = 1;
          workspace_back_and_forth = 1;
          workspace_center_on = 1;
          movefocus_cycles_fullscreen = true;
          window_direction_monitor_fallback = true;
        };

        # Gestures configuration
        gestures = {
          # New gesture syntax for Hyprland 0.51+
          # Format: gesture = fingers, direction, action, options
          # 3-finger horizontal swipe for workspace switching
          gesture = [
            "3, l, workspace, +1" # 3-finger swipe left to next workspace
            "3, r, workspace, -1" # 3-finger swipe right to previous workspace
            "3, u, workspace, special" # 3-finger swipe up for special workspace
            "3, d, workspace, special" # 3-finger swipe down for special workspace
          ];
        };

        # Autostart applications
        exec-once = [
          "swaybg -o \\* -i ${../../../wallpaper/laptop.jpg} -m fill"
          # waybar is started by home-manager's systemd service
          "mako &"
          "nm-applet --indicator &"
          "bash -c \"mkfifo /tmp/$HYPRLAND_INSTANCE_SIGNATURE.wob && tail -f /tmp/$HYPRLAND_INSTANCE_SIGNATURE.wob | wob & disown\" &"
          "${pkgs.kdePackages.polkit-kde-agent-1}/libexec/polkit-kde-authentication-agent-1 &"
          "systemctl --user import-environment &"
          "hash dbus-update-activation-environment 2>/dev/null &"
          "dbus-update-activation-environment --systemd &"
          "hypridle-wrapper"
        ];

        # Key bindings
        bind = [
          # Main keybinds
          "$mod, RETURN, exec, $terminal"
          "$mod, T, exec, $terminal" # Super+T also opens new terminal
          "$mod, B, exec, $browser"
          "$mod SHIFT, B, exec, wofi-bluetooth" # Bluetooth menu
          "$mod, Q, killactive"
          "$mod SHIFT, M, exec, loginctl terminate-user \"\""
          "$mod, E, exec, ${pkgs.vscode}/bin/code"
          "$mod SHIFT, V, togglefloating"
          "$mod, SPACE, exec, $applauncher"
          "$mod, F, fullscreen"
          "$mod, Y, pin"
          "$mod, J, togglesplit"

          # Screenshots
          ", Print, exec, $shot-region"
          "CTRL, Print, exec, $shot-window"
          "ALT, Print, exec, $shot-screen"

          # Grouping
          "$mod, K, togglegroup"
          "$mod, Tab, changegroupactive, f"

          # Workspace cycling with Alt+Tab (cycle through workspaces with windows)
          "ALT, Tab, workspace, m+1"
          "ALT SHIFT, Tab, workspace, m-1"

          # Focus movement - vim-style jkl;
          "$mod, J, movefocus, l"
          "$mod, K, movefocus, d"
          "$mod, L, movefocus, u"
          "$mod, semicolon, movefocus, r"

          # Gaps
          "$mod SHIFT, G, exec, hyprctl --batch \"keyword general:gaps_out 5;keyword general:gaps_in 3\""
          "$mod, G, exec, hyprctl --batch \"keyword general:gaps_out 0;keyword general:gaps_in 0\""

          # Playback control
          ", XF86AudioPlay, exec, playerctl play-pause"
          ", XF86AudioNext, exec, playerctl next"
          ", XF86AudioPrev, exec, playerctl previous"

          # Lock screen
          "$mod, L, exec, hyprlock"

          # Power menu (logout/restart/shutdown)
          "$mod, BackSpace, exec, wlogout"
          "$mod, O, exec, killall -SIGUSR2 waybar"

          # Window movement
          "$mod SHIFT, J, movewindow, l"
          "$mod SHIFT, K, movewindow, d"
          "$mod SHIFT, L, movewindow, u"
          "$mod SHIFT, semicolon, movewindow, r"

          # Quick resize with keyboard
          "$mod ALT, J, resizeactive, -15 0"
          "$mod ALT, K, resizeactive, 0 15"
          "$mod ALT, L, resizeactive, 0 -15"
          "$mod ALT, semicolon, resizeactive, 15 0"

          # Workspace switching
          "$mod, 1, workspace, 1"
          "$mod, 2, workspace, 2"
          "$mod, 3, workspace, 3"
          "$mod, 4, workspace, 4"
          "$mod, 5, workspace, 5"
          "$mod, 6, workspace, 6"
          "$mod, 7, workspace, 7"
          "$mod, 8, workspace, 8"
          "$mod, 9, workspace, 9"
          "$mod, 0, workspace, 10"

          # Move to workspace
          "$mod CTRL, 1, movetoworkspace, 1"
          "$mod CTRL, 2, movetoworkspace, 2"
          "$mod CTRL, 3, movetoworkspace, 3"
          "$mod CTRL, 4, movetoworkspace, 4"
          "$mod CTRL, 5, movetoworkspace, 5"
          "$mod CTRL, 6, movetoworkspace, 6"
          "$mod CTRL, 7, movetoworkspace, 7"
          "$mod CTRL, 8, movetoworkspace, 8"
          "$mod CTRL, 9, movetoworkspace, 9"
          "$mod CTRL, 0, movetoworkspace, 10"

          # Move silently to workspace
          "$mod SHIFT, 1, movetoworkspacesilent, 1"
          "$mod SHIFT, 2, movetoworkspacesilent, 2"
          "$mod SHIFT, 3, movetoworkspacesilent, 3"
          "$mod SHIFT, 4, movetoworkspacesilent, 4"
          "$mod SHIFT, 5, movetoworkspacesilent, 5"
          "$mod SHIFT, 6, movetoworkspacesilent, 6"
          "$mod SHIFT, 7, movetoworkspacesilent, 7"
          "$mod SHIFT, 8, movetoworkspacesilent, 8"
          "$mod SHIFT, 9, movetoworkspacesilent, 9"
          "$mod SHIFT, 0, movetoworkspacesilent, 10"

          # Workspace navigation
          "$mod, PERIOD, workspace, e+1"
          "$mod, COMMA, workspace, e-1"
          "$mod, mouse_down, workspace, e+1"
          "$mod, mouse_up, workspace, e-1"
          "$mod, slash, workspace, previous"

          # Special workspaces
          "$mod, minus, movetoworkspace, special"
          "$mod, equal, togglespecialworkspace, special"
          "$mod, F1, togglespecialworkspace, scratchpad"
          "$mod ALT SHIFT, F1, movetoworkspacesilent, special:scratchpad"

          # Resize mode activation
          "$mod, R, submap, resize"
        ];

        # Volume control (using bindel for repeat)
        bindel = [
          ", XF86AudioRaiseVolume, exec, wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+ && pkill -RTMIN+8 waybar"
          ", XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- && pkill -RTMIN+8 waybar"
          ", XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle && pkill -RTMIN+8 waybar"
          ", F3, exec, wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+ && pkill -RTMIN+8 waybar"
          ", F2, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- && pkill -RTMIN+8 waybar"
          ", F1, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle && pkill -RTMIN+8 waybar"
          ", F4, exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle && pkill -RTMIN+8 waybar"
          ", XF86MonBrightnessUp, exec, brightnessctl s +5%"
          ", XF86MonBrightnessDown, exec, brightnessctl s 5%-"
          ", F7, exec, brightnessctl s +5%"
          ", F6, exec, brightnessctl s 5%-"
        ];

        # Mouse bindings
        bindm = [
          "$mod, mouse:272, movewindow"
          "$mod, mouse:273, resizewindow"
        ];

        # Lid close/open handling
        bindl = [
          ", switch:on:Lid Switch, exec, systemctl suspend"
          ", switch:off:Lid Switch, exec, hyprctl dispatch dpms on"
        ];

        # Window rules from CachyOS
        windowrule = [
          # Float necessary windows
          "float, class:^(org.pulseaudio.pavucontrol)"
          "float, class:^()$,title:^(Picture in picture)$"
          "float, class:^()$,title:^(Save File)$"
          "float, class:^()$,title:^(Open File)$"
          "float, class:^(LibreWolf)$,title:^(Picture-in-Picture)$"
          "float, class:^(blueman-manager)$"
          "float, class:^(xdg-desktop-portal-gtk|xdg-desktop-portal-kde|xdg-desktop-portal-hyprland)(.*)$"
          "float, class:^(polkit-gnome-authentication-agent-1|hyprpolkitagent|org.org.kde.polkit-kde-authentication-agent-1)(.*)$"
          "float, class:^(CachyOSHello)$"
          "float, class:^(zenity)$"
          "float, class:^()$,title:^(Steam - Self Updater)$"

          # Opacity rules
          "opacity 0.92, class:^(thunar|nemo)$"
          "opacity 0.96, class:^(discord|armcord|webcord)$"
          "opacity 0.95, title:^(QQ|Telegram)$"
          "opacity 0.95, title:^(NetEase Cloud Music Gtk4)$"

          # Picture-in-Picture rules
          "float, title:^(Picture-in-Picture)$"
          "size 960 540, title:^(Picture-in-Picture)$"
          "move 25%-, title:^(Picture-in-Picture)$"

          # Media and file manager rules
          "float, title:^(imv|mpv|danmufloat|termfloat|nemo|ncmpcpp)$"
          "move 25%-, title:^(imv|mpv|danmufloat|termfloat|nemo|ncmpcpp)$"
          "size 960 540, title:^(imv|mpv|danmufloat|termfloat|nemo|ncmpcpp)$"
          "pin, title:^(danmufloat)$"
          "rounding 5, title:^(danmufloat|termfloat)$"

          # Animation rules
          "animation slide right, class:^(kitty|Alacritty)$"
          "noblur, class:^(org.mozilla.firefox)$"

          # Floating window decorations on workspaces 1-10
          "bordersize 2, floating:1, onworkspace:w[fv1-10]"
          "bordercolor $tokyonight_cyan, floating:1, onworkspace:w[fv1-10]"
          "rounding 8, floating:1, onworkspace:w[fv1-10]"

          # Tiling window decorations on workspaces 1-10
          "bordersize 3, floating:0, onworkspace:f[1-10]"
          "rounding 4, floating:0, onworkspace:f[1-10]"
        ];

        # Workspace rules from CachyOS
        workspace = [
          # Smart gaps
          "w[tv1-10], gapsout:5, gapsin:3"
          "f[1], gapsout:5, gapsin:3"
        ];

        # Layer rules from CachyOS
        layerrule = [
          "animation slide top, logout_dialog"
          "animation slide down, waybar"
          "animation fade 50%, wallpaper"
          "blur, rofi"
          "ignorealpha 0, rofi"
        ];
      };

      # Submaps for resize mode
      submaps = {
        resize = {
          settings = {
            bind = [
              ", j, resizeactive, -15 0"
              ", k, resizeactive, 0 15"
              ", l, resizeactive, 0 -15"
              ", semicolon, resizeactive, 15 0"
              ", escape, submap, reset"
            ];
          };
        };
      };
    };
  };
}
