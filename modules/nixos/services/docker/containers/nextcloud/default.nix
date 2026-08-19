# Nextcloud complete office suite module
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.nixos.docker.containers.nextcloud;
  containerName = "nextcloud";
  containerPath = "/var/lib/docker-containers/${containerName}";
in {
  options.modules.nixos.docker.containers.nextcloud = {
    enable = lib.mkEnableOption "Nextcloud office suite with Collabora and OnlyOffice";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "local.solivan.dev";
      description = "Base domain for Nextcloud services";
    };

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "nextcloud";
      description = "Subdomain for Nextcloud";
    };

    dataPath = lib.mkOption {
      type = lib.types.str;
      default = "/home/danny/docker/nextcloud";
      description = "Base path for Nextcloud data";
    };

    dbRootPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default =
        if config.modules.nixos.security.sops.enable
        then "/run/secrets/services/nextcloud/db_root_password"
        else null;
      description = "Path to file containing database root password";
    };

    dbPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default =
        if config.modules.nixos.security.sops.enable
        then "/run/secrets/services/nextcloud/db_password"
        else null;
      description = "Path to file containing database user password";
    };

    dbUser = lib.mkOption {
      type = lib.types.str;
      default = "danny";
      description = "Database user for Nextcloud";
    };

    collaboraPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default =
        if config.modules.nixos.security.sops.enable
        then "/run/secrets/services/nextcloud/collabora_password"
        else null;
      description = "Path to file containing Collabora admin password";
    };

    jwtSecretFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default =
        if config.modules.nixos.security.sops.enable
        then "/run/secrets/services/nextcloud/jwt_secret"
        else null;
      description = "Path to file containing OnlyOffice JWT secret";
    };

    enableCollabora = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Collabora Online office suite";
    };

    enableOnlyOffice = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable OnlyOffice document server";
    };
  };

  config = lib.mkIf cfg.enable {
    # Ensure Docker is enabled
    virtualisation.docker.enable = true;

    # Create required directories
    systemd.tmpfiles.rules = [
      "d ${containerPath} 0755 root root -"
      "d ${cfg.dataPath} 0755 danny users -"
      "d ${cfg.dataPath}/db 0755 999 999 -" # MariaDB user
      "d ${cfg.dataPath}/library 0755 33 33 -" # www-data user
    ];

    # Nextcloud multi-container service
    systemd.services."docker-container-${containerName}" = {
      description = "Nextcloud Office Suite Containers";
      after = ["docker.service" "docker-network-proxy.service"];
      requires = ["docker.service" "docker-network-proxy.service"];
      wantedBy = ["multi-user.target"];

      preStart = ''
        # Copy docker-compose.yml to runtime directory
        cp ${./docker-compose.yml} ${containerPath}/docker-compose.yml

        # Copy init script if exists
        ${lib.optionalString (builtins.pathExists ./init-nextcloud.sh) ''
          cp ${./init-nextcloud.sh} ${containerPath}/init-nextcloud.sh
          chmod +x ${containerPath}/init-nextcloud.sh
        ''}

        # Generate .env file with secrets
        cat > ${containerPath}/.env <<EOF
        ${lib.optionalString (cfg.dbRootPasswordFile != null) ''
          DB_ROOT_PW=$(cat ${cfg.dbRootPasswordFile})
        ''}
        DB_USER=${cfg.dbUser}
        ${lib.optionalString (cfg.dbPasswordFile != null) ''
          DB_PW=$(cat ${cfg.dbPasswordFile})
        ''}
        ${lib.optionalString (cfg.collaboraPasswordFile != null) ''
          COLLABORA_PASSWORD=$(cat ${cfg.collaboraPasswordFile})
        ''}
        ${lib.optionalString (cfg.jwtSecretFile != null) ''
          JWT_SECRET=$(cat ${cfg.jwtSecretFile})
        ''}
        DATA_PATH=${cfg.dataPath}
        DOMAIN=${cfg.domain}
        SUBDOMAIN=${cfg.subdomain}
        EOF

        # Update docker-compose.yml with proper paths
        ${pkgs.yq}/bin/yq -i -y '
          .services."nextcloud-db".volumes[0] = "${cfg.dataPath}/db:/var/lib/mysql" |
          .services.nextcloud.volumes[0] = "${cfg.dataPath}/library:/var/www/html"
        ' ${containerPath}/docker-compose.yml

        # Disable services if not enabled
        ${lib.optionalString (!cfg.enableCollabora) ''
          ${pkgs.yq}/bin/yq -i -y 'del(.services.collabora)' ${containerPath}/docker-compose.yml
        ''}
        ${lib.optionalString (!cfg.enableOnlyOffice) ''
          ${pkgs.yq}/bin/yq -i -y 'del(.services.onlyoffice)' ${containerPath}/docker-compose.yml
        ''}

        # Ensure proper permissions for data directories
        chown -R 999:999 ${cfg.dataPath}/db || true
        chown -R 33:33 ${cfg.dataPath}/library || true
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
