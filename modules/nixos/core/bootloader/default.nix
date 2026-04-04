# NixOS bootloader configuration module
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.modules.nixos.core.bootloader;
in {
  options.modules.nixos.core.bootloader = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable bootloader configuration";
    };

    plymouth = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Plymouth boot splash";
    };
  };

  config = mkIf cfg.enable {
    boot.loader.systemd-boot.enable = true;
    boot.loader.systemd-boot.configurationLimit = 5;
    boot.loader.efi.canTouchEfiVariables = true;

    # Enable systemd in initrd for better Plymouth integration with LUKS
    boot.initrd.systemd.enable = true;

    # Plymouth boot splash
    boot.plymouth = mkIf cfg.plymouth {
      enable = true;
      theme = "bgrt";
    };

    # Kernel parameters for Plymouth with LUKS
    boot.kernelParams =
      if cfg.plymouth
      then [
        "quiet"
        "splash"
        "loglevel=3"
        "rd.systemd.show_status=false"
        "rd.udev.log_level=3"
        "udev.log_priority=3"
        "plymouth.ignore-serial-consoles"
      ]
      else [];

    boot.consoleLogLevel = 0;
    boot.initrd.verbose = false;
  };
}
