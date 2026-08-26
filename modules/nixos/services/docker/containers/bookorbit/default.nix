# BookOrbit library server container module
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.nixos.docker.containers.bookorbit;
  containerName = "bookorbit";
  containerPath = "/var/lib/docker-containers/${containerName}";
  usesTitan = lib.hasPrefix "/mnt/titan" cfg.libraryRootPath;
in {
  options.modules.nixos.docker.containers.bookorbit = {
    enable = lib.mkEnableOption "BookOrbit library server";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "solivan.dev";
      description = "Base domain for BookOrbit";
    };

    localDomain = lib.mkOption {
      type = lib.types.str;
      default = "local.solivan.dev";
      description = "Local domain for BookOrbit";
    };

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "books";
      description = "Subdomain for BookOrbit";
    };

    libraryRootPath = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/titan";
      description = "Host path mounted as BookOrbit's /books library root";
    };

    dataPath = lib.mkOption {
      type = lib.types.str;
      default = "/home/danny/docker/bookorbit/data";
      description = "Local path for BookOrbit application and PostgreSQL data";
    };

    environmentFile = lib.mkOption {
      type = lib.types.str;
      default = "/home/danny/docker/bookorbit/.env";
      description = "Runtime BookOrbit environment file";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = true;

    systemd.tmpfiles.rules = [
      "d ${containerPath} 0755 root root -"
      "d /home/danny/docker/bookorbit 0755 danny users -"
      "d ${cfg.dataPath} 0755 danny users -"
      "d ${cfg.dataPath}/app 0750 danny users -"
      "d ${cfg.dataPath}/postgres 0755 999 999 -"
    ];

    systemd.services."docker-container-${containerName}" = {
      description = "BookOrbit Library Server Container";
      after =
        ["docker.service" "docker-network-proxy.service"]
        ++ lib.optionals usesTitan ["mnt-titan.mount"];
      requires =
        ["docker.service" "docker-network-proxy.service"]
        ++ lib.optionals usesTitan ["mnt-titan.mount"];
      wantedBy = ["multi-user.target"];
      unitConfig = lib.mkIf usesTitan {
        RequiresMountsFor = [cfg.libraryRootPath];
      };

      preStart = ''
        ${lib.optionalString usesTitan ''
          while ! ${pkgs.util-linux}/bin/mountpoint -q /mnt/titan; do
            echo "Waiting for Titan mount"
            sleep 2
          done
        ''}

        while [ ! -d "${cfg.libraryRootPath}" ]; do
          echo "Waiting for BookOrbit library root: ${cfg.libraryRootPath}"
          sleep 2
        done

        mkdir -p "${cfg.dataPath}/postgres"
        chown -R 999:999 "${cfg.dataPath}/postgres" || true

        cp ${./docker-compose.yml} ${containerPath}/docker-compose.yml

        if [ ! -f "${cfg.environmentFile}" ]; then
          install -D -o danny -g users -m 0600 ${./bookorbit.env.example} "${cfg.environmentFile}"
          bookorbit_postgres_password=$(${pkgs.openssl}/bin/openssl rand -hex 32)
          bookorbit_jwt_secret=$(${pkgs.openssl}/bin/openssl rand -hex 32)
          bookorbit_setup_token=$(${pkgs.openssl}/bin/openssl rand -hex 16)
          sed -i \
            -e "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$bookorbit_postgres_password|" \
            -e "s|^JWT_SECRET=.*|JWT_SECRET=$bookorbit_jwt_secret|" \
            -e "s|^SETUP_BOOTSTRAP_TOKEN=.*|SETUP_BOOTSTRAP_TOKEN=$bookorbit_setup_token|" \
            -e "s|^APP_URL=.*|APP_URL=https://${cfg.subdomain}.${cfg.domain}|" \
            -e "s|^BOOKS_HOST_PATH=.*|BOOKS_HOST_PATH=${cfg.libraryRootPath}|" \
            -e "s|^DATA_PATH=.*|DATA_PATH=${cfg.dataPath}|" \
            -e "s|^DOMAIN=.*|DOMAIN=${cfg.domain}|" \
            -e "s|^LOCAL_DOMAIN=.*|LOCAL_DOMAIN=${cfg.localDomain}|" \
            -e "s|^SUBDOMAIN=.*|SUBDOMAIN=${cfg.subdomain}|" \
            "${cfg.environmentFile}"
        fi

        install -o root -g root -m 0600 "${cfg.environmentFile}" ${containerPath}/.env
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
