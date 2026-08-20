# LibbyRip audiobook converter container
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.nixos.docker.containers.libbyrip-converter;
  containerName = "libbyrip-converter";
  containerPath = "/var/lib/docker-containers/${containerName}";
in {
  options.modules.nixos.docker.containers.libbyrip-converter = {
    enable = lib.mkEnableOption "LibbyRip audiobook converter";

    source = lib.mkOption {
      type = lib.types.path;
      default = inputs.libbyrip;
      description = "Pinned LibbyRip source used as the Docker build context";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "local.solivan.dev";
      description = "Base domain for the converter";
    };

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "converter";
      description = "Converter subdomain";
    };

    dataPath = lib.mkOption {
      type = lib.types.str;
      default = "${containerPath}/data";
      description = "Persistent LibbyRip application state";
    };

    uploadPath = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/titan/transfer/upload_audiobooks";
      description = "Titan path for uploaded source files";
    };

    outputPath = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/titan/Audiobooks";
      description = "Titan path for converted audiobooks";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = true;

    systemd.tmpfiles.rules = [
      "d ${containerPath} 0755 root root -"
      "d ${cfg.dataPath} 0755 root root -"
    ];

    systemd.services."docker-container-${containerName}" = {
      description = "LibbyRip Audiobook Converter Container";
      after = ["docker.service" "docker-network-proxy.service" "mnt-titan.mount"];
      requires = ["docker.service" "docker-network-proxy.service" "mnt-titan.mount"];
      wantedBy = ["multi-user.target"];
      unitConfig.RequiresMountsFor = [cfg.uploadPath cfg.outputPath];

      preStart = ''
        while ! ${pkgs.util-linux}/bin/mountpoint -q /mnt/titan; do
          echo "Waiting for Titan mount"
          sleep 2
        done

        test -d ${lib.escapeShellArg cfg.uploadPath}
        test -d ${lib.escapeShellArg cfg.outputPath}

        cp ${./docker-compose.yml} ${containerPath}/docker-compose.yml
        cat > ${containerPath}/.env <<EOF
        LIBBYRIP_SOURCE=${cfg.source}
        DATA_PATH=${cfg.dataPath}
        UPLOAD_PATH=${cfg.uploadPath}
        OUTPUT_PATH=${cfg.outputPath}
        DOMAIN=${cfg.domain}
        SUBDOMAIN=${cfg.subdomain}
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
  };
}
