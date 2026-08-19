# Audiobookshelf audiobook and podcast server module
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.nixos.docker.containers.audiobookshelf;
  containerName = "audiobookshelf";
  containerPath = "/var/lib/docker-containers/${containerName}";
  usesTitan =
    lib.hasPrefix "/mnt/titan" cfg.audiobooksPath
    || lib.hasPrefix "/mnt/titan" cfg.podcastsPath;
in {
  options.modules.nixos.docker.containers.audiobookshelf = {
    enable = lib.mkEnableOption "Audiobookshelf audiobook and podcast server";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "local.solivan.dev";
      description = "Base domain for Audiobookshelf";
    };

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "audiobookshelf";
      description = "Subdomain for Audiobookshelf";
    };

    audiobooksPath = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/titan/Audiobooks";
      description = "Path to audiobooks library";
    };

    podcastsPath = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/titan/Podcasts";
      description = "Path to podcasts library";
    };

    configPath = lib.mkOption {
      type = lib.types.str;
      default = "/home/danny/docker/audiobookshelf/audiobookshelf";
      description = "Path to Audiobookshelf configuration";
    };
  };

  config = lib.mkIf cfg.enable {
    # Ensure Docker is enabled
    virtualisation.docker.enable = true;

    # Create required directories
    systemd.tmpfiles.rules = [
      "d ${containerPath} 0755 root root -"
      "d /home/danny/docker/audiobookshelf 0755 danny users -"
    ];

    # Audiobookshelf container service
    systemd.services."docker-container-${containerName}" = {
      description = "Audiobookshelf Audiobook and Podcast Server Container";
      after =
        ["docker.service" "docker-network-proxy.service"]
        ++ lib.optionals usesTitan ["mnt-titan.mount"];
      # Make Titan mount a hard requirement if paths use it
      requires =
        ["docker.service" "docker-network-proxy.service"]
        ++ lib.optionals usesTitan ["mnt-titan.mount"];
      wantedBy = ["multi-user.target"];
      unitConfig = lib.mkIf usesTitan {
        RequiresMountsFor = [cfg.audiobooksPath cfg.podcastsPath];
      };

      preStart = ''
        ${lib.optionalString usesTitan ''
          echo "Waiting for Titan mount to become active"
          while ! ${pkgs.util-linux}/bin/mountpoint -q /mnt/titan; do
            echo "/mnt/titan is not mounted yet, waiting..."
            sleep 2
          done
        ''}

        # Wait for mount paths to be available
        ${lib.optionalString (lib.hasPrefix "/mnt/titan" cfg.audiobooksPath) ''
          echo "Waiting for audiobooks path: ${cfg.audiobooksPath}"
          while [ ! -d "${cfg.audiobooksPath}" ]; do
            echo "Path not available yet, waiting..."
            sleep 2
          done
        ''}
        ${lib.optionalString (lib.hasPrefix "/mnt/titan" cfg.podcastsPath) ''
          echo "Waiting for podcasts path: ${cfg.podcastsPath}"
          while [ ! -d "${cfg.podcastsPath}" ]; do
            echo "Path not available yet, waiting..."
            sleep 2
          done
        ''}

        # Copy docker-compose.yml to runtime directory
        cp ${./docker-compose.yml} ${containerPath}/docker-compose.yml

        # Create .env file with configuration
        cat > ${containerPath}/.env <<EOF
        PUID=1000
        PGID=1000
        AUDIOBOOKS_PATH=${cfg.audiobooksPath}
        PODCASTS_PATH=${cfg.podcastsPath}
        CONFIG_PATH=${cfg.configPath}
        DOMAIN=${cfg.domain}
        SUBDOMAIN=${cfg.subdomain}
        EOF

        # Ensure config directories have correct permissions
        chown -R danny:users ${cfg.configPath}
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
