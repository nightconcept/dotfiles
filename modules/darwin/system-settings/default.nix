# macOS system settings configuration
{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.modules.darwin.systemSettings;
in {
  options.modules.darwin.systemSettings = {
    enable = mkEnableOption "macOS system settings";

    systemType = mkOption {
      type = types.enum ["laptop" "desktop"];
      default = "laptop";
      description = "Type of system (affects dock and other settings)";
    };
  };

  config = mkIf cfg.enable {
    system.defaults = {
      # Global settings
      NSGlobalDomain = {
        _HIHideMenuBar = false;
      };

      # Finder settings
      finder = {
        FXDefaultSearchScope = "SCcf";
        AppleShowAllExtensions = true;
        FXEnableExtensionChangeWarning = false;
        ShowStatusBar = true;
      };

      # Dock settings based on system type
      dock =
        if cfg.systemType == "desktop"
        then {
          # Desktop dock settings - close to macOS defaults
          autohide = false;
          autohide-delay = 0.5;
          autohide-time-modifier = 0.5;
          show-recents = true;
          static-only = false;
          tilesize = 48;
          magnification = false;
          largesize = 64;
          orientation = "bottom";
          mineffect = "genie";
        }
        else {
          # Laptop dock settings - minimal and autohide
          autohide = true;
          autohide-delay = 0.0;
          autohide-time-modifier = 0.0;
          show-recents = false;
          static-only = true;
        };
    };
  };
}
