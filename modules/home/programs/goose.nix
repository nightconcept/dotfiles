{
  config,
  lib,
  pkgs,
  ...
}: let
  moduleLib = import ../../../lib/module {inherit lib;};
  inherit (moduleLib) mkBoolOpt;

  cfg = config.modules.home.programs.goose;

  goose = pkgs.callPackage ../../../pkgs/goose-cli/package.nix {};
in {
  options.modules.home.programs.goose = {
    enable = mkBoolOpt true "Enable goose AI agent CLI";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [goose];

    # Points goose at Terra's local llama-swap OpenAI-compatible endpoint,
    # same qwen3-35b-mtp (35B total / ~3B active MoE, Qwen 3.6) model pi uses.
    home.sessionVariables = {
      GOOSE_PROVIDER = "openai";
      GOOSE_MODEL = "qwen3-35b-mtp";
      OPENAI_HOST = "http://192.168.1.111:8080";
      OPENAI_API_KEY = "none";
    };
  };
}
