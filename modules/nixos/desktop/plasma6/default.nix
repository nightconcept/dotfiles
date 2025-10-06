# KDE Plasma 6 desktop environment module
{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.modules.nixos.desktop.plasma6;
in {
  options.modules.nixos.desktop.plasma6 = {
    enable = mkEnableOption "KDE Plasma 6 desktop environment";
  };

  config = mkIf cfg.enable {
    services.xserver.enable = true;
    services.displayManager.sddm.enable = true;
    services.desktopManager.plasma6.enable = true;
  };
}
