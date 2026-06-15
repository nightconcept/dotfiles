# Homebrew configuration module for Darwin
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.modules.darwin.homebrew;
in {
  options.modules.darwin.homebrew = {
    enable = mkEnableOption "Homebrew package management";

    systemType = mkOption {
      type = types.enum ["laptop" "desktop"];
      default = "laptop";
      description = "Type of system (affects installed packages)";
    };

    extraCasks = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Additional casks to install";
    };

    extraBrews = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Additional brews to install";
    };
  };

  config = mkIf cfg.enable {
    homebrew = {
      enable = true;
      onActivation = {
        autoUpdate = true;
        cleanup = "zap";
        extraFlags = ["--force-cleanup"];
        upgrade = true;
      };

      taps = [
        "felixkratz/formulae"
      ];

      brews =
        [
          "gettext"
          "pinentry-mac"
          "uv"
          "xz"
        ]
        ++ cfg.extraBrews;

      # nix-darwin does not expose Homebrew's `trusted` Brewfile option yet.
      extraConfig = ''
        brew "felixkratz/formulae/borders", trusted: true
      '';

      casks =
        [
          "calibre"
          "discord"
          "docker-desktop"
          "firefox"
          # "librewolf"
          "ghostty"
          "gitbutler"
          "hiddenbar"
          "mos"
          "nomachine"
          "obsidian"
          "plex"
          "qdirstat"
          "raycast"
          "stretchly"
          "visual-studio-code"
          "vlc"
        ]
        ++ optionals (cfg.systemType == "desktop") [
          "alt-tab"
          "rectangle"
        ]
        ++ cfg.extraCasks;
    };
  };
}
