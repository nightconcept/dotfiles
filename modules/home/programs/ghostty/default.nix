{
  config,
  lib,
  pkgs,
  ...
}: let
  # Import our custom lib functions
  moduleLib = import ../../../../lib/module {inherit lib;};
  inherit (moduleLib) mkBoolOpt;
in {
  options.modules.home.programs.ghostty = {
    enable = mkBoolOpt false "Enable Ghostty terminal emulator";
    configOnly = mkBoolOpt false "Enable Ghostty configuration only (without installing package)";
  };

  config = lib.mkIf (config.modules.home.programs.ghostty.enable || config.modules.home.programs.ghostty.configOnly) {
    programs.ghostty = {
      enable = true;
      # On macOS and non-NixOS Linux, use configOnly mode since ghostty is installed externally
      package = lib.mkIf (pkgs.stdenv.isDarwin || config.modules.home.programs.ghostty.configOnly) (
        pkgs.runCommand "ghostty-dummy" {
          meta.mainProgram = "ghostty";
        } ''
          mkdir -p $out/bin
          touch $out/bin/ghostty
          chmod +x $out/bin/ghostty
        ''
      );

      settings = {
        # Font Configuration - matching wezterm
        font-family = "FiraCode Nerd Font Propo";
        font-size = 14;

        # Theme - Tokyo Night to match wezterm
        theme = "TokyoNight";
        background-opacity = 0.97;

        # General Settings
        scrollback-limit = 7000;
        confirm-close-surface = false;
        auto-update = "off";

        # URL/Link handling (cmd+click on macOS, ctrl+click on Linux is built-in)
        link-url = true;

        # Tab Bar - disable macOS native tabs to work with tiling window managers
        window-decoration = true;
        gtk-tabs-location = "top";

        # macOS-specific: Disable native tabs to prevent window manager conflicts
        macos-non-native-fullscreen = true;
        macos-titlebar-style = "tabs";

        # Mouse Configuration
        mouse-hide-while-typing = true;

        # Shell Integration - explicitly set to fish
        shell-integration = "fish";
        # Available features: cursor, sudo, title, ssh-env, ssh-terminfo
        shell-integration-features = "cursor,sudo,title,ssh-env,ssh-terminfo";

        # Clipboard
        clipboard-read = "allow";
        clipboard-write = "allow";
        clipboard-trim-trailing-spaces = true;

        # Window Settings
        window-padding-x = 4;
        window-padding-y = 4;

        # Performance
        font-feature = [
          "-calt"
          "-liga"
        ];

        # Platform-specific keybindings
        keybind = if pkgs.stdenv.isDarwin then [
          # macOS keybindings (CMD modifier)
          # Disable new_tab to avoid conflicts with tiling window managers (use splits instead)
          "cmd+t=unbind"
          "cmd+w=close_surface"
          "cmd+enter=toggle_fullscreen"
          "cmd+shift+left_bracket=previous_tab"
          "cmd+shift+right_bracket=next_tab"
          "cmd+k=clear_screen"
          "cmd+r=reload_config"

          # Disable cmd+1-9 to avoid conflicts with workspace switching
          "cmd+one=unbind"
          "cmd+two=unbind"
          "cmd+three=unbind"
          "cmd+four=unbind"
          "cmd+five=unbind"
          "cmd+six=unbind"
          "cmd+seven=unbind"
          "cmd+eight=unbind"
          "cmd+nine=unbind"
        ] else [
          # Linux keybindings (CTRL modifier)
          "ctrl+shift+t=new_tab"
          "ctrl+shift+w=close_surface"
          "ctrl+shift+enter=toggle_fullscreen"
          "ctrl+shift+left_bracket=previous_tab"
          "ctrl+shift+right_bracket=next_tab"
          "ctrl+shift+k=clear_screen"
          "ctrl+shift+r=reload_config"
        ];
      };
    };

    # On macOS, ensure ghostty is in PATH for shell integration
    home.sessionPath = lib.mkIf pkgs.stdenv.isDarwin [
      "/Applications/Ghostty.app/Contents/MacOS"
    ];
  };
}
