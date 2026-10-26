# Google Colab CLI (https://github.com/googlecolab/google-colab-cli)
#
# Not in nixpkgs or Homebrew, and it pins jupyter-kernel-client==0.9.0, so it is
# installed as a uv tool (~/.local/bin/colab, already on PATH via fish) during
# activation, the same way terra gets it (modules/linux/programs/colab.py).
# The OAuth token (~/.config/colab-cli/token.json) is never managed here.
{
  config,
  lib,
  pkgs,
  ...
}: let
  moduleLib = import ../../../lib/module {inherit lib;};
  inherit (moduleLib) mkBoolOpt;
  cfg = config.modules.home.programs.colab;
  spec = "google-colab-cli>=0.7.5";
in {
  options.modules.home.programs.colab = {
    enable = mkBoolOpt false "Install the Google Colab CLI as a uv tool";
  };

  config = lib.mkIf cfg.enable {
    home.activation.colabCli = lib.hm.dag.entryAfter ["writeBoundary"] ''
      uv=${pkgs.uv}/bin/uv
      if ! "$uv" tool list 2>/dev/null | grep -q '^google-colab-cli '; then
        # Needs the network; a failure must not break the switch.
        $DRY_RUN_CMD "$uv" tool install '${spec}' \
          || echo "colab: uv tool install failed; run: uv tool install '${spec}'" >&2
      fi
    '';
  };
}
