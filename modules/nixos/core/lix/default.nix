# Lix - Alternative Nix implementation
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
with lib; let
  cfg = config.modules.nixos.core.lix;
in {
  options.modules.nixos.core.lix = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Lix as the Nix implementation (alternative to standard Nix)";
    };
  };

  config = mkIf cfg.enable {
    # Note: The actual Lix module inclusion needs to happen at the system level
    # This option serves as a flag that the host wants to use Lix
    # The tidus host will include the lix-module directly

    assertions = [
      {
        assertion = inputs ? lix-module;
        message = "Lix module requires the lix-module flake input to be defined";
      }
    ];

    # Ensure we're not setting conflicting Nix configurations
    # Lix handles its own nix settings through the overlay
  };
}
