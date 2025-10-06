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
  options.modules.home.programs.alacritty = {
    enable = mkBoolOpt false "Enable Alacritty terminal emulator";
  };

  config = lib.mkIf config.modules.home.programs.alacritty.enable {
    programs.alacritty = {
      enable = true;

      # Using Tokyo Night theme from alacritty-theme package
      theme = "tokyo_night";

      settings = {
        # Font configuration
        font = {
          normal = {
            family = "FiraCode Nerd Font Propo";
            style = "Regular";
          };
          bold = {
            family = "FiraCode Nerd Font Propo";
            style = "Bold";
          };
          italic = {
            family = "FiraCode Nerd Font Propo";
            style = "Light"; # FiraCode doesn't have a true italic, using Light instead
          };
          bold_italic = {
            family = "FiraCode Nerd Font Propo";
            style = "SemiBold"; # Using SemiBold for bold italic
          };
          size = 14.0;
        };

        # Window configuration
        window = {
          padding = {
            x = 3;
            y = 3;
          };
          decorations = "Full";
          opacity = 0.97;
          dynamic_title = true;
        };

        # Scrolling
        scrolling = {
          history = 7000;
          multiplier = 3;
        };

        # Mouse configuration
        mouse = {
          hide_when_typing = false;
        };

        # Selection
        selection = {
          save_to_clipboard = true;
        };

        # Terminal settings
        terminal = lib.mkIf pkgs.stdenv.isDarwin {
          shell = {
            program = "/bin/zsh";
            args = ["-l"];
          };
        };

        # Key bindings - coordinated with Aerospace, Zellij, and Neovim
        keyboard.bindings = [
          # Terminal-level operations
          {
            key = "N";
            mods = "Command";
            action = "CreateNewWindow";
          }
          {
            key = "W";
            mods = "Command";
            action = "Quit";
          }
          {
            key = "Return";
            mods = "Command";
            action = "ToggleFullscreen";
          }

          # Scrolling
          {
            key = "K";
            mods = "Command";
            action = "ClearLogNotice";
          }
          {
            key = "K";
            mods = "Command|Shift";
            chars = "\\u000c";
          } # Clear screen
          {
            key = "PageUp";
            mods = "Shift";
            action = "ScrollPageUp";
          }
          {
            key = "PageDown";
            mods = "Shift";
            action = "ScrollPageDown";
          }
          {
            key = "Home";
            mods = "Shift";
            action = "ScrollToTop";
          }
          {
            key = "End";
            mods = "Shift";
            action = "ScrollToBottom";
          }

          # Font size controls
          {
            key = "Plus";
            mods = "Command";
            action = "IncreaseFontSize";
          }
          {
            key = "Minus";
            mods = "Command";
            action = "DecreaseFontSize";
          }
          {
            key = "Key0";
            mods = "Command";
            action = "ResetFontSize";
          }

          # Copy/Paste
          {
            key = "C";
            mods = "Command";
            action = "Copy";
          }
          {
            key = "V";
            mods = "Command";
            action = "Paste";
          }

          # Vi Mode
          {
            key = "Space";
            mods = "Control|Shift";
            action = "ToggleViMode";
          }
        ];
      };
    };
  };
}
