# Immich photo management system module
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.nixos.docker.containers.immich;
  containerName = "immich";
  containerPath = "/var/lib/docker-containers/${containerName}";
in {
  options.modules.nixos.docker.containers.immich = {
    enable = lib.mkEnableOption "Immich photo management system";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "local.solivan.dev";
      description = "Base domain for Immich";
    };

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "photos";
      description = "Subdomain for Immich";
    };

    uploadLocation = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/titan/Photography/immich";
      description = "Path to photo upload storage";
    };

    dbDataLocation = lib.mkOption {
      type = lib.types.str;
      default = "/home/danny/docker/immich/postgres";
      description = "Path to PostgreSQL database storage";
    };

    dbPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default =
        if config.modules.nixos.security.sops.enable
        then "/run/secrets/services/immich/db_password"
        else null;
      description = "Path to file containing database password";
    };

    timezone = lib.mkOption {
      type = lib.types.str;
      default = "America/Los_Angeles";
      description = "Timezone for Immich";
    };

    version = lib.mkOption {
      type = lib.types.str;
      default = "release";
      description = "Immich version to use";
    };
  };

  config = lib.mkIf cfg.enable {
    # Ensure Docker is enabled
    virtualisation.docker.enable = true;

    # Create required directories
    systemd.tmpfiles.rules = [
      "d ${containerPath} 0755 root root -"
      "d /home/danny/docker/immich 0755 danny users -"
      "d ${cfg.dbDataLocation} 0755 999 999 -" # PostgreSQL user
      "d ${cfg.uploadLocation} 0755 danny users -"
    ];

    # Immich multi-container service
    systemd.services."docker-container-${containerName}" = {
      description = "Immich Photo Management System";
      after = ["docker.service" "docker-network-proxy.service" "mnt-titan.mount"];
      requires = ["docker.service" "docker-network-proxy.service"];
      wants = ["mnt-titan.mount"];
      wantedBy = ["multi-user.target"];

      preStart = ''
        # Copy docker-compose.yml to runtime directory
        cp ${./docker-compose.yml} ${containerPath}/docker-compose.yml

        # Generate .env file with configuration
        cat > ${containerPath}/.env <<EOF
        # Photo storage location
        UPLOAD_LOCATION=${cfg.uploadLocation}

        # Database location (local storage only)
        DB_DATA_LOCATION=${cfg.dbDataLocation}

        # Timezone
        TZ=${cfg.timezone}

        # Immich version
        IMMICH_VERSION=${cfg.version}

        # Database credentials
        DB_USERNAME=postgres
        DB_DATABASE_NAME=immich
        EOF

        # Add password from secrets file
        ${lib.optionalString (cfg.dbPasswordFile != null) ''
          if [ -f ${cfg.dbPasswordFile} ]; then
            echo "DB_PASSWORD=$(cat ${cfg.dbPasswordFile})" >> ${containerPath}/.env
          else
            echo "Error: Database password file not found at ${cfg.dbPasswordFile}"
            exit 1
          fi
        ''}
        ${lib.optionalString (cfg.dbPasswordFile == null) ''
          echo "Error: No database password configured"
          exit 1
        ''}

        # Update docker-compose.yml with proper subdomain
        ${pkgs.yq}/bin/yq -i -y '
          .services."immich-server".labels[2] = "traefik.http.routers.immich.rule=Host(`${cfg.subdomain}.${cfg.domain}`)" |
          .services."immich-server".labels[6] = "traefik.http.routers.immich-secure.rule=Host(`${cfg.subdomain}.${cfg.domain}`)"
        ' ${containerPath}/docker-compose.yml

        # Ensure proper permissions for postgres data
        chown -R 999:999 ${cfg.dbDataLocation} || true
      '';

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        WorkingDirectory = containerPath;
        ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d --wait --wait-timeout 180";
        ExecStop = "${pkgs.docker-compose}/bin/docker-compose down";
        ExecReload = "${pkgs.docker-compose}/bin/docker-compose restart";
      };
    };
  };
}
