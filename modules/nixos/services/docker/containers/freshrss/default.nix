# FreshRSS RSS Feed Aggregator Container Module
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.nixos.docker.containers.freshrss;
  containerName = "freshrss";
  containerPath = "/var/lib/docker-containers/${containerName}";
in {
  options.modules.nixos.docker.containers.freshrss = {
    enable = lib.mkEnableOption "FreshRSS RSS feed aggregator container";

    timezone = lib.mkOption {
      type = lib.types.str;
      default = "America/Chicago";
      description = "Timezone for FreshRSS";
    };

    cronMinInterval = lib.mkOption {
      type = lib.types.int;
      default = 15;
      description = "Minimum interval in minutes between feed updates";
    };

    baseUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://freshrss.local.solivan.dev";
      description = "Base URL for FreshRSS";
      example = "https://freshrss.example.com";
    };

    port = lib.mkOption {
      type = lib.types.int;
      default = 8081;
      description = "Port for FreshRSS web interface";
    };

    dataPath = lib.mkOption {
      type = lib.types.str;
      default = "${containerPath}/data";
      description = "Path to FreshRSS data directory";
    };

    extensionsPath = lib.mkOption {
      type = lib.types.str;
      default = "${containerPath}/extensions";
      description = "Path to FreshRSS extensions directory";
    };

    enableWatchtower = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Watchtower auto-updates";
    };

    database = {
      type = lib.mkOption {
        type = lib.types.enum ["sqlite" "mysql" "postgres"];
        default = "sqlite";
        description = "Database type for FreshRSS";
      };

      host = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Database host (for MySQL/PostgreSQL)";
      };

      port = lib.mkOption {
        type = lib.types.int;
        default = 3306;
        description = "Database port (for MySQL/PostgreSQL)";
      };

      name = lib.mkOption {
        type = lib.types.str;
        default = "freshrss";
        description = "Database name (for MySQL/PostgreSQL)";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "freshrss";
        description = "Database user (for MySQL/PostgreSQL)";
      };

      password = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Database password (for MySQL/PostgreSQL)";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Ensure Docker is enabled
    virtualisation.docker.enable = true;

    # Create required directories
    systemd.tmpfiles.rules = [
      "d ${containerPath} 0755 root root -"
      "d ${cfg.dataPath} 0755 root root -"
      "d ${cfg.extensionsPath} 0755 root root -"
    ];

    # FreshRSS container service
    systemd.services."docker-container-${containerName}" = {
      description = "FreshRSS RSS Feed Aggregator Container";
      after = ["docker.service" "docker-network-proxy.service"];
      requires = ["docker.service" "docker-network-proxy.service"];
      wantedBy = ["multi-user.target"];

      preStart = ''
        # Copy docker-compose.yml to runtime directory
        cp ${./docker-compose.yml} ${containerPath}/docker-compose.yml

        # Create .env file with configuration
        cat > ${containerPath}/.env <<EOF
        TZ=${cfg.timezone}
        CRON_MIN=${toString cfg.cronMinInterval}
        BASE_URL=${cfg.baseUrl}
        PORT=${toString cfg.port}
        DATA_PATH=${cfg.dataPath}
        EXTENSIONS_PATH=${cfg.extensionsPath}
        DB_TYPE=${cfg.database.type}
        DB_HOST=${cfg.database.host}
        DB_PORT=${toString cfg.database.port}
        DB_NAME=${cfg.database.name}
        DB_USER=${cfg.database.user}
        DB_PASS=${cfg.database.password}
        WATCHTOWER_ENABLE=${toString cfg.enableWatchtower}
        EOF
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

    # Open firewall port
    networking.firewall.allowedTCPPorts = [cfg.port];
  };
}
