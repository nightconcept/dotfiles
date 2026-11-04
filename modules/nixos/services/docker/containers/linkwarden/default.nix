{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.nixos.docker.containers.linkwarden;
  containerPath = "/var/lib/docker-containers/linkwarden";
in {
  options.modules.nixos.docker.containers.linkwarden.enable = lib.mkEnableOption "Linkwarden bookmark manager";

  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = true;
    systemd.tmpfiles.rules = [
      "d ${containerPath} 0755 root root -"
    ];

    systemd.services.docker-container-linkwarden = {
      description = "Linkwarden Containers";
      after = ["docker.service" "docker-network-proxy.service"];
      requires = ["docker.service" "docker-network-proxy.service"];
      wantedBy = ["multi-user.target"];
      preStart = ''
        cp ${./docker-compose.yml} ${containerPath}/docker-compose.yml
        # Keep credentials across rebuilds and commit them atomically on first start.
        if [ ! -s ${containerPath}/.env ]; then
          umask 077
          {
            echo "POSTGRES_PASSWORD=$(${pkgs.openssl}/bin/openssl rand -hex 32)"
            echo "NEXTAUTH_SECRET=$(${pkgs.openssl}/bin/openssl rand -hex 32)"
            echo "MEILI_MASTER_KEY=$(${pkgs.openssl}/bin/openssl rand -hex 32)"
          } > ${containerPath}/.env.tmp
          mv ${containerPath}/.env.tmp ${containerPath}/.env
        fi
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
