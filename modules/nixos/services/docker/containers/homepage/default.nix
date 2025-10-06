# Homepage Dashboard Container Module
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.nixos.docker.containers.homepage;
  containerName = "homepage";
  containerPath = "/var/lib/docker-containers/${containerName}";
in {
  options.modules.nixos.docker.containers.homepage = {
    enable = lib.mkEnableOption "Homepage dashboard";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "local.solivan.dev";
      description = "Base domain for Homepage";
    };

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "home";
      description = "Subdomain for Homepage";
    };

    port = lib.mkOption {
      type = lib.types.int;
      default = 3000;
      description = "Port for Homepage web interface";
    };

    configPath = lib.mkOption {
      type = lib.types.str;
      default = "${containerPath}/config";
      description = "Path to Homepage configuration";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = true;

    systemd.tmpfiles.rules = [
      "d ${containerPath} 0755 root root -"
      "d ${cfg.configPath} 0755 root root -"
    ];

    systemd.services."docker-container-${containerName}" = {
      description = "Homepage Dashboard Container";
      after = ["docker.service" "docker-network-proxy.service"];
      requires = ["docker.service" "docker-network-proxy.service"];
      wantedBy = ["multi-user.target"];

      preStart = ''
        # Copy docker-compose.yml to runtime directory
        cp ${./docker-compose.yml} ${containerPath}/docker-compose.yml

        # Generate .env file
        cat > ${containerPath}/.env <<EOF
        CONFIG_PATH=${cfg.configPath}
        HOMEPAGE_DOMAIN=${cfg.subdomain}.${cfg.domain}
        EOF
      '';

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        WorkingDirectory = containerPath;
        ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d";
        ExecStop = "${pkgs.docker-compose}/bin/docker-compose down";
      };
    };

    networking.firewall.allowedTCPPorts = [cfg.port];
  };
}
