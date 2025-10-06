# Prowlarr ABB (AudioBook Bay) Indexer Module
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.nixos.docker.containers.prowlarr-abb;
  containerName = "prowlarr-abb";
  containerPath = "/var/lib/docker-containers/${containerName}";
in {
  options.modules.nixos.docker.containers.prowlarr-abb = {
    enable = lib.mkEnableOption "Prowlarr ABB audiobook indexer";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "local.solivan.dev";
      description = "Base domain for Prowlarr ABB";
    };

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "prowlarr-abb";
      description = "Subdomain for Prowlarr ABB";
    };

    port = lib.mkOption {
      type = lib.types.int;
      default = 9697;
      description = "Host port for Prowlarr ABB";
    };

    configPath = lib.mkOption {
      type = lib.types.str;
      default = "/home/danny/docker/prowlarr-abb/prowlarr-abb";
      description = "Path to Prowlarr ABB configuration";
    };

    timezone = lib.mkOption {
      type = lib.types.str;
      default = "America/Los_Angeles";
      description = "Timezone for Prowlarr ABB";
    };
  };

  config = lib.mkIf cfg.enable {
    # Ensure Docker is enabled
    virtualisation.docker.enable = true;

    # Create required directories
    systemd.tmpfiles.rules = [
      "d ${containerPath} 0755 root root -"
      "d /home/danny/docker/prowlarr-abb 0755 danny users -"
    ];

    # Prowlarr ABB container service
    systemd.services."docker-container-${containerName}" = {
      description = "Prowlarr ABB Audiobook Indexer Container";
      after = ["docker.service" "docker-network-proxy.service"];
      requires = ["docker.service" "docker-network-proxy.service"];
      wantedBy = ["multi-user.target"];

      preStart = ''
        # Copy docker-compose.yml to runtime directory
        cp ${./docker-compose.yml} ${containerPath}/docker-compose.yml

        # Create .env file with configuration
        cat > ${containerPath}/.env <<EOF
        PUID=1000
        PGID=1000
        TZ=${cfg.timezone}
        CONFIG_PATH=${cfg.configPath}
        PORT=${toString cfg.port}
        DOMAIN=${cfg.domain}
        SUBDOMAIN=${cfg.subdomain}
        EOF

        # Ensure config directory has correct permissions
        chown -R danny:users ${cfg.configPath}
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
