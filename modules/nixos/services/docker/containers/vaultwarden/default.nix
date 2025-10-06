# Vaultwarden Password Manager Container Module
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.nixos.docker.containers.vaultwarden;
  containerName = "vaultwarden";
  containerPath = "/var/lib/docker-containers/${containerName}";
in {
  options.modules.nixos.docker.containers.vaultwarden = {
    enable = lib.mkEnableOption "Vaultwarden password manager";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "local.solivan.dev";
      description = "Base domain for Vaultwarden";
    };

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "vaultwarden";
      description = "Subdomain for Vaultwarden";
    };

    dataPath = lib.mkOption {
      type = lib.types.str;
      default = "/home/danny/docker/vaultwarden/data";
      description = "Path to Vaultwarden data directory";
    };

    adminTokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default =
        if config.modules.nixos.security.sops.enable
        then "/run/secrets/services/vaultwarden/admin_token"
        else null;
      description = "Path to file containing Vaultwarden admin token";
    };
  };

  config = lib.mkIf cfg.enable {
    # Ensure Docker is enabled
    virtualisation.docker.enable = true;

    # Create required directories
    systemd.tmpfiles.rules = [
      "d ${containerPath} 0755 root root -"
      "d /home/danny/docker/vaultwarden 0755 danny users -"
    ];

    # Vaultwarden container service
    systemd.services."docker-container-${containerName}" = {
      description = "Vaultwarden Password Manager Container";
      after = ["docker.service" "docker-network-proxy.service"];
      requires = ["docker.service" "docker-network-proxy.service"];
      wantedBy = ["multi-user.target"];

      preStart = ''
        # Copy docker-compose.yml to runtime directory
        cp ${./docker-compose.yml} ${containerPath}/docker-compose.yml

        # Generate .env file with admin token
        cat > ${containerPath}/.env <<EOF
        DATA_PATH=${cfg.dataPath}
        DOMAIN=${cfg.domain}
        SUBDOMAIN=${cfg.subdomain}
        ${lib.optionalString (cfg.adminTokenFile != null) ''
          ADMIN_TOKEN=$(cat ${cfg.adminTokenFile})
        ''}
        EOF

        # Ensure data directory has correct permissions
        chown -R danny:users ${cfg.dataPath}
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
