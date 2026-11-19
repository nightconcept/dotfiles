{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.nixos.docker.containers.pricebuddy;
  containerPath = "/var/lib/docker-containers/pricebuddy";
in {
  options.modules.nixos.docker.containers.pricebuddy.enable = lib.mkEnableOption "PriceBuddy price tracker";

  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = true;
    systemd.tmpfiles.rules = ["d ${containerPath} 0700 root root -"];
    systemd.services.docker-container-pricebuddy = {
      description = "PriceBuddy price tracker";
      after = ["docker.service" "docker-network-proxy.service" "docker-container-searxng.service"];
      requires = ["docker.service" "docker-network-proxy.service"];
      wantedBy = ["multi-user.target"];
      restartTriggers = [./docker-compose.yml];
      preStart = ''
        umask 077
        install -m 0644 ${./docker-compose.yml} ${containerPath}/docker-compose.yml
        if [ ! -s ${containerPath}/.env ]; then
          {
            echo "DB_PASSWORD=$(${pkgs.openssl}/bin/openssl rand -hex 32)"
            echo "DB_ROOT_PASSWORD=$(${pkgs.openssl}/bin/openssl rand -hex 32)"
            echo "ADMIN_PASSWORD=$(${pkgs.openssl}/bin/openssl rand -hex 24)"
          } > ${containerPath}/.env.tmp
          mv ${containerPath}/.env.tmp ${containerPath}/.env
        fi
        touch ${containerPath}/app.env
        chmod 0600 ${containerPath}/app.env
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        WorkingDirectory = containerPath;
        ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d --wait --wait-timeout 300";
        ExecStop = "${pkgs.docker-compose}/bin/docker-compose down";
        ExecReload = "${pkgs.docker-compose}/bin/docker-compose restart";
        TimeoutStartSec = 600;
      };
    };
  };
}
