# Printing services configuration module
{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.modules.nixos.hardware.printing;
in {
  options.modules.nixos.hardware.printing = {
    enable = mkEnableOption "Printing support";
  };

  config = mkIf cfg.enable {
    services.printing.enable = true;
  };
}
