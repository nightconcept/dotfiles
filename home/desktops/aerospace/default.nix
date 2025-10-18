# AeroSpace Desktop Environment for macOS
{
  config,
  lib,
  pkgs,
  ...
}: {
  options.desktops.aerospace = {
    enable = lib.mkEnableOption "AeroSpace window manager desktop environment for macOS";
  };

  config = lib.mkIf config.desktops.aerospace.enable {
    # Enable aerospace window manager
    programs.aerospace = {
      enable = true;
      userSettings = {
        # Start AeroSpace at login
        start-at-login = true;

        # You can use it to add commands that run after AeroSpace startup.
        after-startup-command = [
          "exec-and-forget /opt/homebrew/bin/borders active_color=0xff7aa2f7 inactive_color=0xff565f89 width=3.0"
        ];

        # Normalizations
        enable-normalization-flatten-containers = true;
        enable-normalization-opposite-orientation-for-nested-containers = true;

        # Layout settings
        accordion-padding = 30;
        default-root-container-layout = "tiles";
        default-root-container-orientation = "auto";

        # Key mapping
        "key-mapping".preset = "qwerty";

        # No workspace change notifications needed for default menu bar

        gaps = {
          inner.horizontal = 15;
          inner.vertical = 15;
          outer.left = 12;
          outer.bottom = 12;
          outer.top = 12;
          outer.right = 12;
        };

        mode.main.binding = {
          # Layout commands
          ctrl-slash = "layout tiles horizontal vertical";
          ctrl-comma = "layout accordion horizontal vertical";

          # Close window
          ctrl-q = "close";
          ctrl-shift-c = "close";

          # Application launching
          ctrl-enter = "exec-and-forget open -n /Applications/Ghostty.app";
          ctrl-b = "exec-and-forget open -a 'Firefox'";
          ctrl-e = "exec-and-forget open -a 'Visual Studio Code'";
          ctrl-f = "exec-and-forget open -a 'Finder'";

          # Navigation - vim-style jkl;
          ctrl-j = ["focus left" "move-mouse window-lazy-center"];
          ctrl-k = ["focus down" "move-mouse window-lazy-center"];
          ctrl-l = ["focus up" "move-mouse window-lazy-center"];
          ctrl-semicolon = ["focus right" "move-mouse window-lazy-center"];

          # Move windows
          ctrl-shift-j = "move left";
          ctrl-shift-k = "move down";
          ctrl-shift-l = "move up";
          ctrl-shift-semicolon = "move right";

          # Window resizing
          ctrl-shift-minus = "resize smart -50";
          ctrl-shift-equal = "resize smart +50";

          # Workspace navigation - full 1-10 support
          ctrl-1 = "workspace 1";
          ctrl-2 = "workspace 2";
          ctrl-3 = "workspace 3";
          ctrl-4 = "workspace 4";
          ctrl-5 = "workspace 5";
          ctrl-6 = "workspace 6";
          ctrl-7 = "workspace 7";
          ctrl-8 = "workspace 8";
          ctrl-9 = "workspace 9";
          ctrl-0 = "workspace 10";

          # Move window to workspace
          ctrl-shift-1 = "move-node-to-workspace 1";
          ctrl-shift-2 = "move-node-to-workspace 2";
          ctrl-shift-3 = "move-node-to-workspace 3";
          ctrl-shift-4 = "move-node-to-workspace 4";
          ctrl-shift-5 = "move-node-to-workspace 5";
          ctrl-shift-6 = "move-node-to-workspace 6";
          ctrl-shift-7 = "move-node-to-workspace 7";
          ctrl-shift-8 = "move-node-to-workspace 8";
          ctrl-shift-9 = "move-node-to-workspace 9";
          ctrl-shift-0 = "move-node-to-workspace 10";

          # Workspace switching - cycle through all workspaces with windows
          ctrl-tab = "workspace next";
          ctrl-shift-tab = "workspace prev";

          # Tiling controls
          ctrl-shift-f = "fullscreen";
          ctrl-shift-w = "layout floating tiling";
          ctrl-shift-s = "layout v_accordion";
          ctrl-shift-t = "layout h_accordion";
          ctrl-shift-e = "layout tiles horizontal vertical";
          ctrl-shift-d = "resize width 1280";

          # Mode switching
          ctrl-shift-m = "mode service";
          ctrl-shift-g = "mode lock";
        };

        mode.service.binding = {
          r = "reload-config";
          f = ["flatten-workspace-tree" "mode main"];
          backspace = ["close-all-windows-but-current" "mode main"];

          ctrl-shift-j = ["join-with left" "mode main"];
          ctrl-shift-k = ["join-with down" "mode main"];
          ctrl-shift-l = ["join-with up" "mode main"];
          ctrl-shift-semicolon = ["join-with right" "mode main"];

          enter = "mode main";
          esc = "mode main";
        };

        mode.lock.binding = {
          enter = "mode main";
          esc = "mode main";
        };

        on-focused-monitor-changed = ["move-mouse monitor-lazy-center"];
      };
    };

    # JankyBorders configuration
    # Note: JankyBorders is installed via Homebrew, this module only manages the config
    xdg.configFile."borders/bordersrc" = {
      text = ''
        #!/bin/bash

        # JankyBorders configuration - Tokyo Night default theme
        # Colors from Tokyo Night default color palette
        options=(
            style=round
            width=3.0
            hidpi=off
            active_color=0xff7aa2f7     # Tokyo Night blue - active window border
            inactive_color=0xff565f89   # Tokyo Night grey - inactive window border
        )

        borders "''${options[@]}"
      '';
      executable = true;
    };
  };
}
