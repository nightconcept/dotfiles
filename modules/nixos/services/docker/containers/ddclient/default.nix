# DDClient Dynamic DNS Container Module
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.nixos.docker.containers.ddclient;
  containerName = "ddclient";
  containerPath = "/var/lib/docker-containers/${containerName}";
in {
  options.modules.nixos.docker.containers.ddclient = {
    enable = lib.mkEnableOption "DDClient dynamic DNS updater";

    configPath = lib.mkOption {
      type = lib.types.str;
      default = "${containerPath}/config";
      description = "Path to DDClient configuration file";
    };

    passwordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default =
        if config.modules.nixos.security.sops.enable
        then "/run/secrets/services/ddclient/password"
        else null;
      description = "Path to file containing DDClient password";
    };
  };

  config = lib.mkIf cfg.enable {
    # Ensure Docker is enabled
    virtualisation.docker.enable = true;

    # Create required directories
    systemd.tmpfiles.rules = [
      "d ${containerPath} 0755 root root -"
      "d ${cfg.configPath} 0755 root root -"
    ];

    # DDClient container service
    systemd.services."docker-container-${containerName}" = {
      description = "DDClient Dynamic DNS Update Container";
      after = ["docker.service" "network-online.target"];
      requires = ["docker.service"];
      wants = ["network-online.target"];
      wantedBy = ["multi-user.target"];

      preStart = ''
        # Copy docker-compose.yml to runtime directory
        cp ${./docker-compose.yml} ${containerPath}/docker-compose.yml

        # Generate .env file if needed
        cat > ${containerPath}/.env <<EOF
        CONFIG_PATH=${cfg.configPath}
        EOF

        # Copy and process config template
        ${lib.optionalString (builtins.pathExists ./config/ddclient.conf.template) ''
          if [ -n "${toString cfg.passwordFile}" ] && [ -f "${cfg.passwordFile}" ]; then
            PASSWORD=$(cat ${cfg.passwordFile})
            sed "s/SOPS_PASSWORD/$PASSWORD/g" ${./config/ddclient.conf.template} > ${cfg.configPath}/ddclient.conf
          else
            cp ${./config/ddclient.conf.template} ${cfg.configPath}/ddclient.conf
          fi
        ''}
      '';

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        WorkingDirectory = containerPath;
        ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d";
        ExecStop = "${pkgs.docker-compose}/bin/docker-compose down";
        ExecReload = "${pkgs.docker-compose}/bin/docker-compose restart";
      };
    };
  };
}
