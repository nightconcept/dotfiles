# Calibre E-book Library Container Module
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.nixos.docker.containers.calibre;
  containerName = "calibre";
  containerPath = "/var/lib/docker-containers/${containerName}";
in {
  options.modules.nixos.docker.containers.calibre = {
    enable = lib.mkEnableOption "Calibre e-book library server";
  };

  config = lib.mkIf cfg.enable {
    # Ensure Docker is enabled
    virtualisation.docker.enable = true;

    # Create required directories
    systemd.tmpfiles.rules = [
      "d ${containerPath} 0755 root root -"
      "d /home/danny/docker/calibre 0755 danny users -"
    ];

    # Calibre container service
    systemd.services."docker-container-${containerName}" = {
      description = "Calibre E-book Library Container";
      after = ["docker.service" "docker-network-proxy.service" "mnt-titan.mount"];
      requires = ["docker.service" "docker-network-proxy.service"];
      bindsTo = ["mnt-titan.mount"];
      wantedBy = ["multi-user.target"];

      preStart = ''
        # Copy docker-compose.yml to runtime directory
        cp ${./docker-compose.yml} ${containerPath}/docker-compose.yml
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

    # Open firewall ports for Calibre
    networking.firewall.allowedTCPPorts = [8085 8086 8181];
  };
}
