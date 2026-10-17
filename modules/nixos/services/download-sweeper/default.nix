# Download sweeper service module
# Periodically sweeps /mnt/titan/downloads to prune already-imported media,
# remove spam executables, and clean up empty folders.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.modules.nixos.services.downloadSweeper;

  downloadSweeperScript = pkgs.writers.writePython3Bin "download-sweeper" {} (
    builtins.readFile ./sweep_downloads.py
  );

  cmdArgs = escapeShellArgs (
    [
      "--downloads-dir"
      cfg.downloadsDir
      "--qbittorrent-host"
      cfg.qbittorrentHost
      "--qbittorrent-port"
      (toString cfg.qbittorrentPort)
      "--qbittorrent-user"
      cfg.qbittorrentUser
      "--qbittorrent-password-file"
      cfg.qbittorrentPasswordFile
      "--sonarr-url"
      cfg.sonarrUrl
      "--sonarr-config"
      cfg.sonarrConfig
      "--radarr-url"
      cfg.radarrUrl
      "--radarr-config"
      cfg.radarrConfig
      "--min-age-minutes"
      (toString cfg.minAgeMinutes)
    ]
    ++ (concatMap (dir: ["--library-dir" dir]) cfg.libraryDirs)
    ++ (optional cfg.dryRun "--dry-run")
  );
in {
  options.modules.nixos.services.downloadSweeper = {
    enable = mkEnableOption "Periodic download sweeper service";

    downloadsDir = mkOption {
      type = types.str;
      default = "/mnt/titan/downloads";
      description = "Path to downloads directory to sweep";
    };

    libraryDirs = mkOption {
      type = types.listOf types.str;
      default = [
        "/mnt/titan/TVShows"
        "/mnt/titan/Movies"
        "/mnt/titan/Audiobooks"
      ];
      description = "Destination library directories to check for moved media";
    };

    schedule = mkOption {
      type = types.str;
      default = "hourly";
      description = "Systemd OnCalendar schedule string (default: hourly)";
    };

    minAgeMinutes = mkOption {
      type = types.int;
      default = 60;
      description = "Minimum age in minutes before items can be pruned";
    };

    qbittorrentHost = mkOption {
      type = types.str;
      default = "192.168.1.117";
      description = "qBittorrent WebUI host";
    };

    qbittorrentPort = mkOption {
      type = types.int;
      default = 8112;
      description = "qBittorrent WebUI port";
    };

    qbittorrentUser = mkOption {
      type = types.str;
      default = "danny";
      description = "qBittorrent username";
    };

    qbittorrentPasswordFile = mkOption {
      type = types.str;
      default = "/run/secrets/vpn/qbittorrent_password";
      description = "Path to qBittorrent password file";
    };

    sonarrUrl = mkOption {
      type = types.str;
      default = "http://127.0.0.1:8989";
      description = "Sonarr base URL";
    };

    sonarrConfig = mkOption {
      type = types.str;
      default = "/home/danny/docker/sonarr/config/config.xml";
      description = "Path to Sonarr config.xml containing API key";
    };

    radarrUrl = mkOption {
      type = types.str;
      default = "http://127.0.0.1:7878";
      description = "Radarr base URL";
    };

    radarrConfig = mkOption {
      type = types.str;
      default = "/home/danny/docker/radarr/config/config.xml";
      description = "Path to Radarr config.xml containing API key";
    };

    dryRun = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to run in dry-run mode (no files deleted)";
    };

    user = mkOption {
      type = types.str;
      default = "danny";
      description = "User to run the service under";
    };

    group = mkOption {
      type = types.str;
      default = "users";
      description = "Group to run the service under";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [downloadSweeperScript];

    systemd.services.download-sweeper = {
      description = "Download directory sweeper and prune service";
      after = ["mnt-titan.mount" "network-online.target" "docker.service"];
      wants = ["network-online.target"];
      requires = ["mnt-titan.mount"];

      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;
        ExecStart = "${downloadSweeperScript}/bin/download-sweeper ${cmdArgs}";
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };

    systemd.timers.download-sweeper = {
      description = "Run download-sweeper on schedule";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = cfg.schedule;
        Persistent = true;
      };
    };
  };
}
