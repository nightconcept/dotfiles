# USB automount configuration module
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.modules.nixos.hardware.usbAutomount;
in {
  options.modules.nixos.hardware.usbAutomount = {
    enable = mkEnableOption "USB drive automounting";
  };

  config = mkIf cfg.enable {
    services.udev.enable = true;
    services.udev.extraRules = ''
      ACTION=="add", SUBSYSTEMS=="usb", SUBSYSTEM=="block", ENV{ID_FS_USAGE}=="filesystem", RUN{program}+="${pkgs.systemd}/bin/systemd-mount --no-block --automount=yes --collect $devnode /media"
    '';
  };
}
