# Apple Intelligence removal via pared (https://github.com/4evy/pared)
# Needs macOS 27+ on Apple silicon; on older releases cleanup fails and retries next activation.
# Block future downloads by installing /etc/pared/disable-apple-intelligence.mobileconfig once.
{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.modules.darwin.pared;
in {
  options.modules.darwin.pared.enable = mkOption {
    type = types.bool;
    default = true;
    description = "Disable Apple Intelligence features and remove their downloaded models";
  };

  config = mkIf cfg.enable {
    programs.pared.enable = true;
  };
}
