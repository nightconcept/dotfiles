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

  # pi models.json — configures the Ollama cloud provider with GLM-5.1 and DeepSeek V4 Pro.
  # The apiKey uses pi's "!command" syntax so it is evaluated at runtime,
  # reading the SOPS-managed secret from the XDG runtime dir (tmpfs).
  piModelsConfig = pkgs.writeText "pi-models.json" (builtins.toJSON {
    providers = {
      "ollama-cloud" = {
        baseUrl = "https://ollama.com/v1";
        api = "openai-completions";
        apiKey = "!cat $HOME/.local/share/sops/secrets/ollama_api_key";
        models = [
          {
            id = "glm-5.1:cloud";
            name = "GLM-5.1 (Cloud)";
            reasoning = false;
            input = ["text"];
            contextWindow = 198000;
            maxTokens = 40960;
            cost = {
              input = 0.0;
              output = 0.0;
              cacheRead = 0.0;
              cacheWrite = 0.0;
            };
            compat = {
              supportsDeveloperRole = false;
              supportsReasoningEffort = false;
            };
          }
          {
            id = "deepseek-v4-pro:cloud";
            name = "DeepSeek V4 Pro (Cloud)";
            reasoning = true;
            input = ["text"];
            contextWindow = 1000000;
            maxTokens = 384000;
            cost = {
              input = 0.0;
              output = 0.0;
              cacheRead = 0.0;
              cacheWrite = 0.0;
            };
            compat = {
              supportsDeveloperRole = true;
              supportsReasoningEffort = true;
            };
          }
        ];
      };
    };
  });
in {
  options.modules.home.programs.pi = {
    enable = mkBoolOpt true "Enable pi terminal coding harness";

    ollama-cloud = {
      enable = mkBoolOpt true "Enable Ollama cloud provider with GLM-5.1 and DeepSeek V4 Pro";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [pi];

    home.file.".pi/agent/models.json" = lib.mkIf cfg.ollama-cloud.enable {
      source = piModelsConfig;
    };
  };
}
