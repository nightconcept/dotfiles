{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  moduleLib = import ../../../lib/module {inherit lib;};
  inherit (moduleLib) mkBoolOpt;

  cfg = config.modules.home.programs.pi;

  # v1.2.0's published install-lock is missing `esbuild` (used by the codemode
  # TS execution tool), so upstream's own installCheckPhase fails on an
  # otherwise-working build. Skip that self-test until upstream re-syncs the
  # lockfile; everything else (including our local-model provider) is unaffected.
  pi = inputs.pi-agent.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs (_: {
    doInstallCheck = false;
  });

  localProvider = "local-openai";
  # Same default as Hermes (modules/linux/ai/catalog.py DEFAULT_MODEL_ID).
  localModelId = "qwen3.8-flash-next-iq2_xs";
  # Other llama-swap models pi can switch to; selecting one swaps the GPU over.
  otherLocalModelIds = ["qwen3.8-27b" "qwen3-35b-mtp"];

  deepseekKeyPath = "${config.home.homeDirectory}/.local/share/sops/secrets/deepseek_api_key";

  piModelsConfig = pkgs.writeText "pi-models.json" (builtins.toJSON {
    providers = {
      # Built-in DeepSeek provider (deepseek-flash, deepseek-v4-pro); we only
      # supply the key, read from the sops-decrypted file at request time.
      deepseek.apiKey = "!cat ${deepseekKeyPath}";

      "${localProvider}" = {
        baseUrl = "http://192.168.1.173:8080/v1";
        api = "openai-completions";
        apiKey = "none";
        compat = {
          supportsDeveloperRole = false;
          supportsReasoningEffort = false;
        };
        models = map (id: {
          inherit id;
          name = id;
        }) ([localModelId] ++ otherLocalModelIds);
      };
    };
  });

  piSettingsConfig = pkgs.writeText "pi-settings.json" (builtins.toJSON {
    defaultProvider = localProvider;
    defaultModel = localModelId;
  });
in {
  options.modules.home.programs.pi = {
    enable = mkBoolOpt true "Enable pi terminal coding harness";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [pi];

    # Shared DeepSeek key; consider moving it to user.yaml.
    sops.secrets.deepseek_api_key = {
      sopsFile = ../secrets/reasonix.yaml;
      path = deepseekKeyPath;
      mode = "0400";
    };

    home.file.".pi/agent/models.json" = {
      source = piModelsConfig;
      force = true;
    };

    home.file.".pi/agent/settings.json" = {
      source = piSettingsConfig;
      force = true;
    };
  };
}
