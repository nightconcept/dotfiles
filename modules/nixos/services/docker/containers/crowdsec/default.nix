# CrowdSec Security Engine Container Module
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.nixos.docker.containers.crowdsec;
  containerName = "crowdsec";
  containerPath = "/var/lib/docker-containers/${containerName}";
in {
  options.modules.nixos.docker.containers.crowdsec = {
    enable = lib.mkEnableOption "CrowdSec security engine and Traefik bouncer";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "local.solivan.dev";
      description = "Base domain for CrowdSec";
    };

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "crowdsec";
      description = "Subdomain for CrowdSec dashboard";
    };

    configPath = lib.mkOption {
      type = lib.types.str;
      default = "${containerPath}/config";
      description = "Path to CrowdSec configuration files";
    };

    dataPath = lib.mkOption {
      type = lib.types.str;
      default = "${containerPath}/data";
      description = "Path to CrowdSec data directory";
    };

    traefik = {
      logPath = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/docker-containers/traefik/logs";
        description = "Path to Traefik logs for CrowdSec to monitor";
      };
    };

    secrets = {
      enrollKeyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default =
          if config.modules.nixos.security.sops.enable
          then "/run/secrets/services/crowdsec/enroll_key"
          else null;
        description = "Path to file containing CrowdSec enrollment key for console";
      };

      bouncerKeyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default =
          if config.modules.nixos.security.sops.enable
          then "/run/secrets/services/crowdsec/bouncer_key"
          else null;
        description = "Path to file containing CrowdSec bouncer API key";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Ensure Docker is enabled
    virtualisation.docker.enable = true;

    # Create required directories
    systemd.tmpfiles.rules = [
      "d ${containerPath} 0755 root root -"
      "d ${cfg.configPath} 0755 root root -"
      "d ${cfg.dataPath} 0755 root root -"
      "d ${cfg.configPath}/acquis 0755 root root -"
    ];

    # CrowdSec container service
    systemd.services."docker-container-${containerName}" = {
      description = "CrowdSec Security Engine Container";
      after = ["docker.service" "docker-network-proxy.service" "sops-install-secrets.service"];
      requires = ["docker.service" "docker-network-proxy.service" "sops-install-secrets.service"];
      wantedBy = ["multi-user.target"];

      preStart = ''
        # Copy docker-compose.yml to runtime directory
        cp ${./docker-compose.yml} ${containerPath}/docker-compose.yml

        # Generate .env file
        cat > ${containerPath}/.env <<EOF
        CONFIG_PATH=${cfg.configPath}
        DATA_PATH=${cfg.dataPath}
        DOMAIN=${cfg.domain}
        SUBDOMAIN=${cfg.subdomain}
        TRAEFIK_LOG_PATH=${cfg.traefik.logPath}
        ${lib.optionalString (cfg.secrets.enrollKeyFile != null) ''
          ENROLL_KEY=$(cat ${cfg.secrets.enrollKeyFile})
        ''}
        ${lib.optionalString (cfg.secrets.bouncerKeyFile != null) ''
          BOUNCER_KEY=$(cat ${cfg.secrets.bouncerKeyFile})
        ''}
        EOF

        # Create acquis.yaml for log sources
        cat > ${cfg.configPath}/acquis.yaml <<'ACQUIS'
        ---
        # Traefik access logs
        filenames:
          - /var/log/traefik/access.log
        labels:
          type: traefik
        ---
        # System authentication logs
        filenames:
          - /var/log/auth.log
          - /var/log/syslog
        labels:
          type: syslog
        ACQUIS

        # Create initial collections configuration if it doesn't exist
        if [ ! -f ${cfg.configPath}/collections.yaml ]; then
          cat > ${cfg.configPath}/collections.yaml <<'COLLECTIONS'
        # Base collections for common attack patterns
        collections:
          - crowdsecurity/traefik
          - crowdsecurity/http-cve
          - crowdsecurity/whitelist-good-actors
          - crowdsecurity/iptables
          - crowdsecurity/linux
          - crowdsecurity/sshd
        COLLECTIONS
        fi
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
