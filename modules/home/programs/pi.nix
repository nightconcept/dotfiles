{
  config,
  lib,
  pkgs,
  ...
}: let
  moduleLib = import ../../../lib/module {inherit lib;};
  inherit (moduleLib) mkBoolOpt;

  cfg = config.modules.home.programs.pi;

  pi = pkgs.callPackage ../../../pkgs/pi/package.nix {};

  piModelsConfig = pkgs.writeText "pi-models.json" (builtins.toJSON {
    providers = {
      "local-openai" = {
        baseUrl = "http://192.168.1.111:8080/v1";
        api = "openai-completions";
        apiKey = "none";
        compat = {
          supportsDeveloperRole = false;
          supportsReasoningEffort = false;
        };
        models = [
          {
            id = "qwen3.6-35b-a3b";
            name = "qwen3.6-35b-a3b";
          }
        ];
      };
    };
  });

  piSettingsConfig = pkgs.writeText "pi-settings.json" (builtins.toJSON {
    shellPath = "/usr/bin/bash";
    defaultProvider = "local-openai";
    defaultModel = "qwen3.6-35b-a3b";
  });
in {
  options.modules.home.programs.pi = {
    enable = mkBoolOpt true "Enable pi terminal coding harness";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [pi];

    home.file.".pi/agent/models.json".source = piModelsConfig;
    home.file.".pi/agent/settings.json".source = piSettingsConfig;
  };
}
