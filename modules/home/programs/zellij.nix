{
  config,
  lib,
  pkgs,
  ...
}: let
  # Import our custom lib functions
  moduleLib = import ../../../lib/module {inherit lib;};
  inherit (moduleLib) mkBoolOpt enabled disabled;
in {
  options.modules.home.programs.zellij = {
    enable = mkBoolOpt false "Enable Zellij terminal multiplexer";
  };

  config = lib.mkIf config.modules.home.programs.zellij.enable {
    programs.zellij = {
      enable = true;

      # Enable shell integration for auto-start
      enableFishIntegration = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
    };

    # Write config directly as KDL file
    xdg.configFile."zellij/config.kdl".text = ''
      theme "tokyo-night-dark"

      // Disable UI elements and tips
      simplified_ui true
      pane_frames false
      show_startup_tips false

      keybinds {
        normal {
          bind "Ctrl t" { NewTab; }
          bind "Ctrl w" { CloseTab; }
          bind "Alt Tab" { GoToNextTab; }
          bind "Alt Shift Tab" { GoToPreviousTab; }
          bind "Ctrl a" { SwitchToMode "tmux"; }

          // Pane navigation with Ctrl+arrow keys
          bind "Ctrl Left" { MoveFocus "Left"; }
          bind "Ctrl Down" { MoveFocus "Down"; }
          bind "Ctrl Up" { MoveFocus "Up"; }
          bind "Ctrl Right" { MoveFocus "Right"; }
        }

        tmux {
          // Pane navigation with vim keys (still available)
          bind "h" { MoveFocus "Left"; SwitchToMode "Normal"; }
          bind "j" { MoveFocus "Down"; SwitchToMode "Normal"; }
          bind "k" { MoveFocus "Up"; SwitchToMode "Normal"; }
          bind "l" { MoveFocus "Right"; SwitchToMode "Normal"; }

          // Pane movement
          bind "H" { MovePane "Left"; SwitchToMode "Normal"; }
          bind "J" { MovePane "Down"; SwitchToMode "Normal"; }
          bind "K" { MovePane "Up"; SwitchToMode "Normal"; }
          bind "L" { MovePane "Right"; SwitchToMode "Normal"; }

          // Pane creation
          bind "|" { NewPane "Right"; SwitchToMode "Normal"; }
          bind "-" { NewPane "Down"; SwitchToMode "Normal"; }

          // Tab operations
          bind "n" { GoToNextTab; SwitchToMode "Normal"; }
          bind "p" { GoToPreviousTab; SwitchToMode "Normal"; }
          bind "c" { NewTab; SwitchToMode "Normal"; }
          bind "x" { CloseTab; SwitchToMode "Normal"; }

          // Tab switching by number
          bind "1" { GoToTab 1; SwitchToMode "Normal"; }
          bind "2" { GoToTab 2; SwitchToMode "Normal"; }
          bind "3" { GoToTab 3; SwitchToMode "Normal"; }
          bind "4" { GoToTab 4; SwitchToMode "Normal"; }
          bind "5" { GoToTab 5; SwitchToMode "Normal"; }
          bind "6" { GoToTab 6; SwitchToMode "Normal"; }
          bind "7" { GoToTab 7; SwitchToMode "Normal"; }
          bind "8" { GoToTab 8; SwitchToMode "Normal"; }
          bind "9" { GoToTab 9; SwitchToMode "Normal"; }

          // Exit tmux mode
          bind "Esc" { SwitchToMode "Normal"; }
        }
      }

      ui {
        pane_frames {
          rounded_corners true
          hide_session_name false
        }
      }

      themes {
        tokyo-night-dark {
          bg "#1a1b26"
          fg "#c0caf5"
          red "#f7768e"
          green "#9ece6a"
          yellow "#e0af68"
          blue "#7aa2f7"
          orange "#ff9e64"
          magenta "#bb9af7"
          cyan "#7dcfff"
          black "#1a1b26"
          white "#c0caf5"
          gray "#565f89"
        }
      }
    '';
  };
}
