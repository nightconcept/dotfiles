# Seerr media request management container module.
# Seerr is the supported successor to Overseerr and Jellyseerr.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.nixos.docker.containers.seerr;
  containerName = "seerr";
  containerPath = "/var/lib/docker-containers/${containerName}";
in {
  options.modules.nixos.docker.containers.seerr = {
    enable = lib.mkEnableOption "Seerr media request management";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "solivan.dev";
      description = "Public base domain for Seerr";
    };

    localDomain = lib.mkOption {
      type = lib.types.str;
      default = "local.solivan.dev";
      description = "Local base domain for Seerr";
    };

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "requests";
      description = "Subdomain for Seerr";
    };

    configPath = lib.mkOption {
      type = lib.types.str;
      default = "/home/danny/docker/seerr/config";
      description = "Path to persistent Seerr configuration and database files";
    };

    timezone = lib.mkOption {
      type = lib.types.str;
      default = "America/Los_Angeles";
      description = "Timezone used by Seerr";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = true;

    systemd.tmpfiles.rules = [
      "d ${containerPath} 0755 root root -"
      "d /home/danny/docker/seerr 0755 danny users -"
      "d ${cfg.configPath} 0750 1000 1000 -"
    ];

    systemd.services."docker-container-${containerName}" = {
      description = "Seerr Media Request Manager Container";
      after = ["docker.service" "docker-network-proxy.service"];
      requires = ["docker.service" "docker-network-proxy.service"];
      wantedBy = ["multi-user.target"];

      preStart = ''
        cp ${./docker-compose.yml} ${containerPath}/docker-compose.yml

        cat > ${containerPath}/.env <<EOF
        CONFIG_PATH=${cfg.configPath}
        DOMAIN=${cfg.domain}
        LOCAL_DOMAIN=${cfg.localDomain}
        SUBDOMAIN=${cfg.subdomain}
        TZ=${cfg.timezone}
        EOF

        mkdir -p ${cfg.configPath}
        chown -R 1000:1000 ${cfg.configPath}
      '';

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        WorkingDirectory = containerPath;
        ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d --wait --wait-timeout 300";
        ExecStop = "${pkgs.docker-compose}/bin/docker-compose down";
        ExecReload = "${pkgs.docker-compose}/bin/docker-compose restart";
      };
    };
  };
}
