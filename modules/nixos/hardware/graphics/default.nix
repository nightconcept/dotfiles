# Graphics/OpenGL configuration module
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.modules.nixos.hardware.graphics;
in {
  options.modules.nixos.hardware.graphics = {
    enable = mkEnableOption "Graphics/OpenGL support";
  };

  config = mkIf cfg.enable {
    hardware.graphics = {
      enable = true;
      enable32Bit = true;
      extraPackages = with pkgs; [
        intel-media-driver
        libvdpau-va-gl
      ];
    };
  };
}
