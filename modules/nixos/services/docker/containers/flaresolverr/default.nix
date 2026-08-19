# FlareSolverr Cloudflare Solver Container Module
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.nixos.docker.containers.flaresolverr;
  containerName = "flaresolverr";
  containerPath = "/var/lib/docker-containers/${containerName}";
in {
  options.modules.nixos.docker.containers.flaresolverr = {
    enable = lib.mkEnableOption "FlareSolverr cloudflare bypass service";

    port = lib.mkOption {
      type = lib.types.int;
      default = 8191;
      description = "Port for FlareSolverr";
    };

    logLevel = lib.mkOption {
      type = lib.types.str;
      default = "info";
      description = "Log level (error, warn, info, debug)";
    };

    captchaSolver = lib.mkOption {
      type = lib.types.str;
      default = "none";
      description = "Captcha solver to use";
    };
  };

  config = lib.mkIf cfg.enable {
    # Ensure Docker is enabled
    virtualisation.docker.enable = true;

    # Create required directories
    systemd.tmpfiles.rules = [
      "d ${containerPath} 0755 root root -"
    ];

    # FlareSolverr container service
    systemd.services."docker-container-${containerName}" = {
      description = "FlareSolverr Cloudflare Bypass Container";
      after = ["docker.service" "network-online.target"];
      requires = ["docker.service"];
      wants = ["network-online.target"];
      wantedBy = ["multi-user.target"];

      preStart = ''
        # Copy docker-compose.yml to runtime directory
        cp ${./docker-compose.yml} ${containerPath}/docker-compose.yml

        # Generate .env file
        cat > ${containerPath}/.env <<EOF
        PORT=${toString cfg.port}
        LOG_LEVEL=${cfg.logLevel}
        CAPTCHA_SOLVER=${cfg.captchaSolver}
        EOF
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

    # Open firewall port
    networking.firewall.allowedTCPPorts = [cfg.port];
  };
}
