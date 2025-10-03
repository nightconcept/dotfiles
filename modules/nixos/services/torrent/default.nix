{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkIf mkMerge;
  cfg = config.modules.nixos.services.torrent;

  # Import our custom lib functions
  moduleLib = import ../../../../lib/module { inherit lib; };
  inherit (moduleLib) mkBoolOpt mkOpt enabled disabled;
in
{
  options.modules.nixos.services.torrent = {
    enable = mkBoolOpt false "Enable qBittorrent torrent service with privacy settings";

    user = mkOpt lib.types.str "danny" "User to run qBittorrent service as";

    downloadDir = mkOpt lib.types.str "/mnt/titan/downloads" "Directory for downloads";

    configDir = mkOpt lib.types.str "/var/lib/torrent" "Directory for qBittorrent configuration";

    qbittorrent = {
      enable = mkBoolOpt true "Enable qBittorrent service";
      webUIPort = mkOpt lib.types.port 8080 "Port for qBittorrent Web UI";
      torrentPort = mkOpt lib.types.port 6881 "Port for BitTorrent traffic";
      randomizePorts = mkBoolOpt true "Randomize torrent port on each restart";
      openFirewall = mkBoolOpt true "Open firewall ports for qBittorrent";
      username = mkOpt lib.types.str "danny" "qBittorrent Web UI username";
      passwordFile = mkOpt (lib.types.nullOr lib.types.path) null "Path to file containing qBittorrent password (from SOPS)";
      passwordHashFile = mkOpt (lib.types.nullOr lib.types.path) null "Path to file containing qBittorrent PBKDF2 hash (from SOPS)";
      uploadRateLimit = mkOpt lib.types.int 100 "Upload rate limit in KiBytes/second (100 KB/s default, 0 = unlimited)";
      downloadRateLimit = mkOpt lib.types.int 0 "Download rate limit in bytes/second (0 = unlimited)";

      # Privacy settings
      anonymousMode = mkBoolOpt true "Enable anonymous mode (no client/version info sent)";
      encryption = mkBoolOpt true "Force encryption for all connections";
      disableDHT = mkBoolOpt true "Disable DHT for increased privacy";
      disablePEX = mkBoolOpt true "Disable Peer Exchange for increased privacy";
      disableLSD = mkBoolOpt true "Disable Local Service Discovery";

      # Connection limits
      maxRatio = mkOpt lib.types.float 2.0 "Maximum seeding ratio before stopping";
      maxActiveDownloads = mkOpt lib.types.int 3 "Maximum concurrent downloads";
      maxConnections = mkOpt lib.types.int 100 "Maximum total connections";
      maxConnectionsPerTorrent = mkOpt lib.types.int 50 "Maximum connections per torrent";

      # VPN interface binding (auto-detect NordVPN interface)
      vpnInterface = mkOpt (lib.types.nullOr lib.types.str) null "VPN interface to bind to (null = auto-detect)";
    };

    autoremove = {
      enable = mkBoolOpt true "Enable autoremove-torrents service";
      intervalMinutes = mkOpt lib.types.int 10 "How often to run autoremove-torrents (in minutes)";
      strategies = mkOpt lib.types.attrs {
        default_strategy = {
          remove = "seeding_time > 604800 or ratio > 2.0"; # Remove after 1 week or 2.0 ratio
          delete_data = true;
        };
      } "Autoremove strategies configuration";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    # Common configuration
    {
      # Create required directories for configuration
      systemd.tmpfiles.rules = [
        "d ${cfg.configDir} 0755 ${cfg.user} users -"
        "d ${cfg.configDir}/qbittorrent 0755 ${cfg.user} users -"
        "d ${cfg.configDir}/qbittorrent/qBittorrent 0755 ${cfg.user} users -"
        "d ${cfg.configDir}/qbittorrent/qBittorrent/cache 0755 ${cfg.user} users -"
        "d ${cfg.configDir}/qbittorrent/qBittorrent/config 0755 ${cfg.user} users -"
        "d ${cfg.configDir}/qbittorrent/qBittorrent/data 0755 ${cfg.user} users -"
        "d ${cfg.configDir}/qbittorrent/qBittorrent/data/logs 0755 ${cfg.user} users -"
        "d ${cfg.downloadDir} 0755 ${cfg.user} users -"  # Create download directory
      ];
    }

    # qBittorrent configuration
    (mkIf cfg.qbittorrent.enable {
      # qBittorrent-nox service (headless with web UI)
      systemd.services.qbittorrent = {
        description = "qBittorrent-nox service";
        after = [ "network.target" "mnt-titan.mount" ];
        requires = [ "mnt-titan.mount" ];  # Ensure titan mount is available
        wantedBy = [ "multi-user.target" ];

        preStart = lib.mkIf (cfg.qbittorrent.passwordHashFile != null) ''
          # Ensure config directory exists
          mkdir -p ${cfg.configDir}/qbittorrent/qBittorrent/config
          mkdir -p ${cfg.configDir}/qbittorrent/qBittorrent/data/logs

          # Generate random port if enabled
          ${lib.optionalString cfg.qbittorrent.randomizePorts ''
            RANDOM_PORT=$((30000 + RANDOM % 30000))  # Random port between 30000-60000
            echo "Using randomized port: $RANDOM_PORT"
          ''}

          # Generate qBittorrent config with PBKDF2 hash from SOPS
          if [ -f "${cfg.qbittorrent.passwordHashFile}" ]; then
            echo "Generating qBittorrent configuration with enhanced privacy settings..."

            # Read PBKDF2 hash from SOPS
            HASH=$(cat "${cfg.qbittorrent.passwordHashFile}")

            cat > ${cfg.configDir}/qbittorrent/qBittorrent/config/qBittorrent.conf << EOF
          [Application]
          FileLogger\\Age=1
          FileLogger\\AgeType=1
          FileLogger\\Backup=true
          FileLogger\\DeleteOld=true
          FileLogger\\Enabled=true
          FileLogger\\MaxSizeBytes=66560
          FileLogger\\Path=${cfg.configDir}/qbittorrent/qBittorrent/data/logs

          [BitTorrent]
          Session\\AddTorrentStopped=false
          Session\\AnonymousMode=${if cfg.qbittorrent.anonymousMode then "true" else "false"}
          Session\\DefaultSavePath=${cfg.downloadDir}
          Session\\DHTEnabled=${if cfg.qbittorrent.disableDHT then "false" else "true"}
          Session\\Encryption=${if cfg.qbittorrent.encryption then "1" else "0"}
          Session\\GlobalMaxRatio=${toString cfg.qbittorrent.maxRatio}
          Session\\GlobalUPSpeedLimit=${toString cfg.qbittorrent.uploadRateLimit}
          Session\\GlobalDLSpeedLimit=${toString cfg.qbittorrent.downloadRateLimit}
          ${lib.optionalString (cfg.qbittorrent.vpnInterface != null) ''
          Session\\Interface=${cfg.qbittorrent.vpnInterface}
          Session\\InterfaceName=${cfg.qbittorrent.vpnInterface}
          ''}
          Session\\LSDEnabled=${if cfg.qbittorrent.disableLSD then "false" else "true"}
          Session\\MaxActiveDownloads=${toString cfg.qbittorrent.maxActiveDownloads}
          Session\\MaxConnections=${toString cfg.qbittorrent.maxConnections}
          Session\\MaxConnectionsPerTorrent=${toString cfg.qbittorrent.maxConnectionsPerTorrent}
          Session\\PeXEnabled=${if cfg.qbittorrent.disablePEX then "false" else "true"}
          Session\\Port=''${RANDOM_PORT:-${toString cfg.qbittorrent.torrentPort}}
          Session\\QueueingSystemEnabled=true
          Session\\RequireEncryption=${if cfg.qbittorrent.encryption then "true" else "false"}
          Session\\ShareLimitAction=Stop

          [Core]
          AutoDeleteAddedTorrentFile=Never

          [LegalNotice]
          Accepted=true

          [Meta]
          MigrationVersion=8

          [Network]
          Proxy\\HostnameLookupEnabled=false

          [Preferences]
          Bittorrent\\MaxUploadsPerTorrent=4
          Connection\\GlobalDLLimitAlt=10
          Connection\\GlobalULLimitAlt=10
          Connection\\PortRangeMin=${toString cfg.qbittorrent.torrentPort}
          Downloads\\SavePath=${cfg.downloadDir}
          General\\Locale=en
          WebUI\\CSRFProtection=false
          WebUI\\LocalHostAuth=false
          WebUI\\Password_PBKDF2="@ByteArray($HASH)"
          WebUI\\Port=${toString cfg.qbittorrent.webUIPort}
          WebUI\\Username=${cfg.qbittorrent.username}

          [RSS]
          AutoDownloader\\DownloadRepacks=true
          EOF

            chown ${cfg.user}:users ${cfg.configDir}/qbittorrent/qBittorrent/config/qBittorrent.conf
            chmod 600 ${cfg.configDir}/qbittorrent/qBittorrent/config/qBittorrent.conf

            echo "qBittorrent configuration generated with username: ${cfg.qbittorrent.username}"
          else
            echo "Warning: Password hash file not found at ${cfg.qbittorrent.passwordHashFile}"
            echo "qBittorrent will start with a temporary password"
          fi
        '';

        serviceConfig = {
          Type = "simple";
          User = cfg.user;
          Group = "users";  # Use the 'users' group instead of username
          PermissionsStartOnly = true;  # Allow preStart to run as root

          # Configure qBittorrent with download directory and profile location
          ExecStart = ''
            ${pkgs.qbittorrent-nox}/bin/qbittorrent-nox \
              --confirm-legal-notice \
              --webui-port=${toString cfg.qbittorrent.webUIPort} \
              --profile=${cfg.configDir}/qbittorrent \
              --save-path=${cfg.downloadDir}
          '';

          Restart = "on-failure";
          RestartSec = "10s";

          # Security hardening
          PrivateTmp = true;
          ProtectSystem = "strict";
          ReadWritePaths = [
            cfg.configDir
            cfg.downloadDir
            "/mnt/titan"  # Ensure access to titan mount
          ];
          NoNewPrivileges = true;
        };
      };

      # Firewall rules for qBittorrent
      networking.firewall = mkIf cfg.qbittorrent.openFirewall {
        allowedTCPPorts = [
          cfg.qbittorrent.webUIPort
          cfg.qbittorrent.torrentPort
        ];
        allowedUDPPorts = [
          cfg.qbittorrent.torrentPort
        ];
      };

      # Install required packages
      environment.systemPackages = with pkgs; [
        qbittorrent-nox
      ];
    })

    # Autoremove-torrents configuration
    (mkIf cfg.autoremove.enable (let
      # Create Python environment with autoremove-torrents
      autoremoveTorrents = pkgs.python3.pkgs.buildPythonPackage rec {
        pname = "autoremove-torrents";
        version = "1.5.5";
        format = "setuptools";

        src = pkgs.fetchFromGitHub {
          owner = "jerrymakesjelly";
          repo = "autoremove-torrents";
          rev = version;
          sha256 = "sha256-XKH7LtJusQIgPxRETeqw+2guFXQhaJaRzgcVujRXk00=";
        };

        propagatedBuildInputs = with pkgs.python3.pkgs; [
          pyyaml
          requests
          ply
        ];

        doCheck = false;
      };

      pythonEnv = pkgs.python3.withPackages (ps: [
        autoremoveTorrents
      ]);
    in {
      # Install Python environment with autoremove-torrents
      environment.systemPackages = [ pythonEnv ];

      # Create directories
      systemd.tmpfiles.rules = [
        "d /etc/autoremove-torrents 0755 root root -"
        "d /var/log/autoremove-torrents 0755 ${cfg.user} users -"
      ];

      # Generate config at runtime with the actual password
      systemd.services.autoremove-torrents-config = {
        description = "Generate autoremove-torrents configuration";
        wantedBy = [ "autoremove-torrents.service" ];
        before = [ "autoremove-torrents.service" ];

        script = lib.mkIf (cfg.qbittorrent.passwordFile != null) ''
          # Read password from SOPS
          if [ -f "${cfg.qbittorrent.passwordFile}" ]; then
            PASSWORD=$(cat "${cfg.qbittorrent.passwordFile}")

            cat > /etc/autoremove-torrents/config.yml << EOF
          qbittorrent_task:
            client: qbittorrent
            host: http://127.0.0.1:${toString cfg.qbittorrent.webUIPort}
            username: ${cfg.qbittorrent.username}
            password: "$PASSWORD"
            strategies:
          EOF

            # Add strategies from Nix config
            ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: strategy: ''
              echo "      ${name}:" >> /etc/autoremove-torrents/config.yml
              echo "        remove: '${strategy.remove}'" >> /etc/autoremove-torrents/config.yml
              echo "        delete_data: ${if strategy.delete_data then "true" else "false"}" >> /etc/autoremove-torrents/config.yml
            '') cfg.autoremove.strategies)}
          fi
        '';

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
      };

      # Autoremove-torrents systemd service
      systemd.services.autoremove-torrents = {
        description = "Remove torrents automatically according to configured strategies";
        after = [ "qbittorrent.service" ];
        wants = [ "qbittorrent.service" ];

        serviceConfig = {
          Type = "oneshot";
          User = cfg.user;
          Group = "users";

          # Security hardening
          PrivateTmp = true;
          ProtectSystem = "strict";
          ReadWritePaths = [
            "/var/log/autoremove-torrents"
          ];
          NoNewPrivileges = true;
        };

        script = ''
          # Run autoremove-torrents with static config file
          ${pythonEnv}/bin/autoremove-torrents \
            --conf=/etc/autoremove-torrents/config.yml \
            --log=/var/log/autoremove-torrents
        '';
      };

      # Systemd timer for periodic execution
      systemd.timers.autoremove-torrents = {
        description = "Run autoremove-torrents every ${toString cfg.autoremove.intervalMinutes} minutes";
        wantedBy = [ "timers.target" ];

        timerConfig = {
          OnBootSec = "${toString cfg.autoremove.intervalMinutes}min";
          OnUnitActiveSec = "${toString cfg.autoremove.intervalMinutes}min";
          Unit = "autoremove-torrents.service";
        };
      };
    }))
  ]);
}
