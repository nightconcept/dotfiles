# Locale and timezone configuration module
{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.modules.nixos.core.locale;
in {
  options.modules.nixos.core.locale = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable locale configuration";
    };

    timeZone = mkOption {
      type = types.str;
      default = "America/Los_Angeles";
      description = "System timezone";
    };
  };

  config = mkIf cfg.enable {
    time.timeZone = cfg.timeZone;
    i18n.defaultLocale = "en_US.UTF-8";

    i18n.extraLocaleSettings = {
      LC_ADDRESS = "en_US.UTF-8";
      LC_IDENTIFICATION = "en_US.UTF-8";
      LC_MEASUREMENT = "en_US.UTF-8";
      LC_MONETARY = "en_US.UTF-8";
      LC_NAME = "en_US.UTF-8";
      LC_NUMERIC = "en_US.UTF-8";
      LC_PAPER = "en_US.UTF-8";
      LC_TELEPHONE = "en_US.UTF-8";
      LC_TIME = "en_US.UTF-8";
    };
  };
}
