# Sound configuration module
{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.modules.nixos.hardware.sound;
in {
  options.modules.nixos.hardware.sound = {
    enable = mkEnableOption "Sound support";
  };

  config = mkIf cfg.enable {
    services.pulseaudio.enable = false;
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      jack.enable = true;
    };
  };
}
