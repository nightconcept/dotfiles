# Cloudflare Tunnel Container Module
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.nixos.docker.containers.cloudflare-tunnel;
  containerName = "cloudflare-tunnel";
  containerPath = "/var/lib/docker-containers/${containerName}";
in {
  options.modules.nixos.docker.containers.cloudflare-tunnel = {
    enable = lib.mkEnableOption "Cloudflare Tunnel service";

    tunnelTokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default =
        if config.modules.nixos.security.sops.enable
        then "/run/secrets/services/cloudflare-tunnel/tunnel_token"
        else null;
      description = "Path to file containing Cloudflare tunnel token";
    };
  };

  config = lib.mkIf cfg.enable {
    # Ensure Docker is enabled
    virtualisation.docker.enable = true;

    # Create required directories
    systemd.tmpfiles.rules = [
      "d ${containerPath} 0755 root root -"
    ];

    # Cloudflare Tunnel container service
    systemd.services."docker-container-${containerName}" = {
      description = "Cloudflare Tunnel Container";
      after = ["docker.service" "docker-network-proxy.service"];
      requires = ["docker.service" "docker-network-proxy.service"];
      wantedBy = ["multi-user.target"];

      preStart = ''
        # Copy docker-compose.yml to runtime directory
        cp ${./docker-compose.yml} ${containerPath}/docker-compose.yml

        # Generate .env file (initially empty)
        touch ${containerPath}/.env

        # Add tunnel token from file if configured
        ${lib.optionalString (cfg.tunnelTokenFile != null) ''
          if [ -f ${cfg.tunnelTokenFile} ]; then
            echo "TUNNEL_TOKEN=$(cat ${cfg.tunnelTokenFile})" > ${containerPath}/.env
          else
            echo "Error: Cloudflare tunnel token file not found at ${cfg.tunnelTokenFile}"
            exit 1
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
