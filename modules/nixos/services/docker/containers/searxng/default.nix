{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.nixos.docker.containers.searxng;
  containerPath = "/var/lib/docker-containers/searxng";
in {
  options.modules.nixos.docker.containers.searxng.enable =
    lib.mkEnableOption "private SearXNG search service";

  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = true;

    systemd.tmpfiles.rules = [
      "d ${containerPath} 0700 root root -"
      "d ${containerPath}/config 0755 977 977 -"
    ];

    systemd.services.docker-container-searxng = {
      description = "SearXNG Search Container";
      after = ["docker.service" "docker-network-proxy.service"];
      requires = ["docker.service" "docker-network-proxy.service"];
      wantedBy = ["multi-user.target"];
      restartTriggers = [./docker-compose.yml];

      preStart = ''
        umask 077
        install -m 0644 ${./docker-compose.yml} ${containerPath}/docker-compose.yml
        install -d -m 0755 -o 977 -g 977 ${containerPath}/config
        if [ ! -s ${containerPath}/secret-key ]; then
          ${pkgs.openssl}/bin/openssl rand -hex 32 > ${containerPath}/secret-key
        fi
        printf 'SEARXNG_SECRET=%s\n' "$(cat ${containerPath}/secret-key)" > ${containerPath}/.env
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
