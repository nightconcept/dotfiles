{
  config,
  lib,
  pkgs,
  ...
}: let
  moduleLib = import ../../../lib/module {inherit lib;};
  inherit (moduleLib) mkBoolOpt;
  reasonix = pkgs.callPackage ../../../pkgs/reasonix/package.nix {};
  secretPath = "${config.home.homeDirectory}/.local/share/sops/secrets/deepseek_api_key";
  defaultConfig = pkgs.writeText "reasonix-config.toml" ''
    default_model = "deepseek-flash"

    [[providers]]
    name = "deepseek-flash"
    base_url = "https://api.deepseek.com"
    models = ["deepseek-flash"]
    api_key_env = "DEEPSEEK_API_KEY"
  '';
in {
  options.modules.home.programs.reasonix = {
    enable = mkBoolOpt false "Enable the reasonix (deepseek-reasonix) coding agent CLI";
  };

  config = lib.mkIf config.modules.home.programs.reasonix.enable {
    home.packages = [
      reasonix
    ];

    home.activation.reasonixConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
      config_file="${config.home.homeDirectory}/.reasonix/config.toml"
      mkdir -p "$(dirname "$config_file")"
      if [ -f "$config_file" ]; then
        ${pkgs.gnused}/bin/sed -i 's/"deepseek-v4-flash"/"deepseek-flash"/g' "$config_file"
        ${pkgs.gnused}/bin/sed -i 's/^\([[:space:]]*\)model[[:space:]]*=[[:space:]]*"deepseek-flash".*/\1models = ["deepseek-flash"]/' "$config_file"
      else
        install -m 600 ${defaultConfig} "$config_file"
      fi
    '';

    sops.secrets.deepseek_api_key = {
      sopsFile = ../secrets/reasonix.yaml;
      path = secretPath;
      mode = "0400";
    };

    sops.templates."reasonix.env" = {
      path = "${config.home.homeDirectory}/.reasonix/.env";
      mode = "0400";
      content = ''
        DEEPSEEK_API_KEY=${config.sops.placeholder.deepseek_api_key}
      '';
    };
  };
}
