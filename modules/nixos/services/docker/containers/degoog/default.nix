{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.nixos.docker.containers.degoog;
  containerPath = "/var/lib/docker-containers/degoog";
in {
  options.modules.nixos.docker.containers.degoog.enable =
    lib.mkEnableOption "private Degoog search service";

  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = true;

    systemd.tmpfiles.rules = [
      "d ${containerPath} 0700 root root -"
      "d ${containerPath}/data 0750 1000 1000 -"
    ];

    systemd.services.docker-container-degoog = {
      description = "Degoog Search Container";
      after = ["docker.service" "docker-network-proxy.service"];
      requires = ["docker.service" "docker-network-proxy.service"];
      wantedBy = ["multi-user.target"];
      restartTriggers = [./docker-compose.yml];

      preStart = ''
        umask 077
        install -m 0644 ${./docker-compose.yml} ${containerPath}/docker-compose.yml
        install -d -m 0750 -o 1000 -g 1000 ${containerPath}/data
        if [ ! -s ${containerPath}/settings-password ]; then
          ${pkgs.openssl}/bin/openssl rand -hex 24 > ${containerPath}/settings-password
        fi
        printf 'DEGOOG_SETTINGS_PASSWORDS=%s\nDEGOOG_PUBLIC_INSTANCE=false\n' \
          "$(cat ${containerPath}/settings-password)" > ${containerPath}/.env
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
