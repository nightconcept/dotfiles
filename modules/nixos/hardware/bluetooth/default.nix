# Bluetooth configuration module
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.modules.nixos.hardware.bluetooth;
in {
  options.modules.nixos.hardware.bluetooth = {
    enable = mkEnableOption "Bluetooth support";
  };

  config = mkIf cfg.enable {
    hardware.bluetooth.enable = true;
    hardware.bluetooth.powerOnBoot = true;
    services.blueman.enable = true;
  };
}
