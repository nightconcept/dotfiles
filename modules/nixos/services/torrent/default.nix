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

    ipfilter = {
      enable = mkBoolOpt false "Enable automatic IP filter updates";
      updateIntervalHours = mkOpt lib.types.int 24 "How often to update IP filters (in hours)";
      cacheDir = mkOpt lib.types.str "/var/cache/qbittorrent-ipfilter" "Directory for IP filter cache";
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
          ${lib.optionalString cfg.ipfilter.enable ''
          Session\\IPFilteringEnabled=true
          Session\\IPFilterFile=${cfg.configDir}/qbittorrent/qBittorrent/data/ipfilter.dat
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

    # IP Filter configuration
    (mkIf cfg.ipfilter.enable {
      # Create cache directory
      systemd.tmpfiles.rules = [
        "d ${cfg.ipfilter.cacheDir} 0755 ${cfg.user} users -"
        "d ${cfg.configDir}/qbittorrent/qBittorrent/data 0755 ${cfg.user} users -"
      ];

      # IP Filter update script
      systemd.services.qbittorrent-ipfilter-update = {
        description = "Update qBittorrent IP filters";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];

        path = with pkgs; [ curl gzip unzip coreutils gnugrep gawk findutils ];

        script = ''
          set -euo pipefail

          CACHE_DIR="${cfg.ipfilter.cacheDir}"
          OUTPUT_FILE="${cfg.configDir}/qbittorrent/qBittorrent/data/ipfilter.dat"
          TEMP_FILE=$(mktemp)
          BLOCKLIST_DIR="$CACHE_DIR/blocklists"

          mkdir -p "$BLOCKLIST_DIR"
          cd "$BLOCKLIST_DIR"

          echo "Starting IP filter update..."

          # Function to check if file needs updating (simple age check for NixOS)
          check_file_age() {
            local file="$1"
            local max_age=$((${toString cfg.ipfilter.updateIntervalHours} * 3600))

            [ ! -f "$file" ] && return 0

            local file_age=$(($(date +%s) - $(stat -c %Y "$file")))
            [ $file_age -ge $max_age ] && return 0

            return 1
          }

          # Function to download blocklist
          download_blocklist() {
            local url="$1"
            local output="$2"

            if check_file_age "$output"; then
              echo "Downloading $url..."
              if curl -sSL "$url" -o "$output.tmp" --connect-timeout 30 --max-time 120; then
                mv "$output.tmp" "$output"
                echo "Downloaded $(basename "$output")"
              else
                rm -f "$output.tmp"
                echo "Failed to download $url"
                return 1
              fi
            else
              echo "Cached: $(basename "$output")"
            fi
          }

          # Download blocklists
          echo "Downloading blocklists..."
          download_blocklist "http://list.iblocklist.com/?list=ydxerpxkpcfqjaybcssw&fileformat=p2p&archiveformat=gz" "level1.gz" || true
          download_blocklist "http://list.iblocklist.com/?list=dufcxgnbjsdwmwctgfuj&fileformat=p2p&archiveformat=gz" "pedo.gz" || true
          download_blocklist "http://list.iblocklist.com/?list=usrcshglbiilevmyfhse&fileformat=p2p&archiveformat=gz" "hijacked.gz" || true
          download_blocklist "http://list.iblocklist.com/?list=xpbqleszmajjesnzddhv&fileformat=p2p&archiveformat=gz" "dshield.gz" || true
          download_blocklist "http://list.iblocklist.com/?list=ficutxiwawokxlcyoeye&fileformat=p2p&archiveformat=gz" "forumspam.gz" || true
          download_blocklist "http://list.iblocklist.com/?list=togdoptykrlolpddwbvz&fileformat=p2p&archiveformat=gz" "tor.gz" || true
          download_blocklist "http://list.iblocklist.com/?list=gihxqmhyunbxhbmgqrla&fileformat=p2p&archiveformat=gz" "bogon.gz" || true
          download_blocklist "http://list.iblocklist.com/?list=xshktygkujudfnjfioro&fileformat=p2p&archiveformat=gz" "microsoft.gz" || true
          download_blocklist "http://list.iblocklist.com/?list=mcvxsnihddgutbjfbghy&fileformat=p2p&archiveformat=gz" "spider.gz" || true
          download_blocklist "http://list.iblocklist.com/?list=bt_level1&fileformat=p2p&archiveformat=gz" "iblock_level1.gz" || true
          download_blocklist "http://list.iblocklist.com/?list=bt_level2&fileformat=p2p&archiveformat=gz" "iblock_level2.gz" || true
          download_blocklist "http://list.iblocklist.com/?list=bt_level3&fileformat=p2p&archiveformat=gz" "iblock_level3.gz" || true
          download_blocklist "https://raw.githubusercontent.com/Naunter/BT_Blocklists/master/ipfilter.dat" "naunter.dat" || true
          download_blocklist "https://www.biglybt.com/blocklist/level1.gz" "biglybt.gz" || true
          download_blocklist "https://raw.githubusercontent.com/firehol/blocklist-ipsets/master/firehol_level1.netset" "firehol.netset" || true
          download_blocklist "http://www.ipdeny.com/ipblocks/data/countries/cn.zone" "ipdeny_cn.zone" || true
          download_blocklist "https://cinsscore.com/list/ci-badguys.txt" "cins_army.txt" || true
          download_blocklist "https://isc.sans.edu/feeds/block.txt" "dshield.txt" || true
          download_blocklist "https://feodotracker.abuse.ch/downloads/ipblocklist.txt" "feodo.txt" || true
          download_blocklist "https://sslbl.abuse.ch/blacklist/sslipblacklist.txt" "sslbl.txt" || true

          echo "Processing blocklists..."

          # Process all files and extract IPs
          for file in *; do
            if [[ -f "$file" ]]; then
              case "$file" in
                *.gz)
                  zcat "$file" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?(-([0-9]{1,3}\.){3}[0-9]{1,3})?' >> "$TEMP_FILE" || true
                  ;;
                *.dat|*.txt|*.netset|*.zone)
                  grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?(-([0-9]{1,3}\.){3}[0-9]{1,3})?' "$file" >> "$TEMP_FILE" || true
                  ;;
              esac
            fi
          done

          # Count statistics
          TOTAL_COUNT=$(wc -l < "$TEMP_FILE" || echo 0)

          # Sort and remove duplicates
          sort -u "$TEMP_FILE" -o "$TEMP_FILE.sorted"
          FINAL_COUNT=$(wc -l < "$TEMP_FILE.sorted" || echo 0)
          DUPLICATE_COUNT=$((TOTAL_COUNT - FINAL_COUNT))

          echo "Creating IP filter file..."

          # Write header and convert to qBittorrent format
          {
            echo "# qBittorrent IP Filter"
            echo "# Updated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
            echo "# Format: range start-range end, access level"
            echo "# Total unique IPs/ranges: $FINAL_COUNT"
            echo ""

            while IFS= read -r line; do
              if [[ $line =~ ^([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)(/[0-9]+)?$ ]]; then
                if [[ $line == *"/"* ]]; then
                  # CIDR notation - convert to range
                  base_ip="''${BASH_REMATCH[1]}"
                  cidr="''${line#*/}"
                  IFS=. read -r i1 i2 i3 i4 <<< "$base_ip"
                  ip_int=$(( (i1 << 24) + (i2 << 16) + (i3 << 8) + i4 ))
                  mask=$((0xffffffff << (32 - cidr)))
                  net_start=$((ip_int & mask))
                  net_end=$((net_start | ~mask & 0xffffffff))
                  printf "%d.%d.%d.%d-%d.%d.%d.%d,1\n" \
                    $((net_start >> 24 & 0xff)) $((net_start >> 16 & 0xff)) \
                    $((net_start >> 8 & 0xff)) $((net_start & 0xff)) \
                    $((net_end >> 24 & 0xff)) $((net_end >> 16 & 0xff)) \
                    $((net_end >> 8 & 0xff)) $((net_end & 0xff))
                else
                  # Single IP
                  echo "$line-$line,1"
                fi
              elif [[ $line =~ ^([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)-([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
                # Already in range format
                echo "$line,1"
              fi
            done < "$TEMP_FILE.sorted"
          } > "$OUTPUT_FILE.tmp"

          # Atomic replacement
          mv "$OUTPUT_FILE.tmp" "$OUTPUT_FILE"
          chown ${cfg.user}:users "$OUTPUT_FILE"

          # Cleanup
          rm -f "$TEMP_FILE" "$TEMP_FILE.sorted"

          echo "IP filter update complete!"
          echo "- Total IPs found: $TOTAL_COUNT"
          echo "- Duplicates removed: $DUPLICATE_COUNT"
          echo "- Final unique IPs: $FINAL_COUNT"
          echo "- Output: $OUTPUT_FILE"
        '';

        serviceConfig = {
          Type = "oneshot";
          User = cfg.user;
          Group = "users";

          # Security hardening
          PrivateTmp = true;
          ProtectSystem = "strict";
          ReadWritePaths = [
            cfg.ipfilter.cacheDir
            cfg.configDir
          ];
          NoNewPrivileges = true;
        };
      };

      # Timer for periodic updates
      systemd.timers.qbittorrent-ipfilter-update = {
        description = "Update qBittorrent IP filters every ${toString cfg.ipfilter.updateIntervalHours} hours";
        wantedBy = [ "timers.target" ];

        timerConfig = {
          OnBootSec = "5min";  # Run 5 minutes after boot
          OnUnitActiveSec = "${toString cfg.ipfilter.updateIntervalHours}h";
          Unit = "qbittorrent-ipfilter-update.service";
        };
      };

      # Make qBittorrent service depend on initial IP filter
      systemd.services.qbittorrent = {
        wants = [ "qbittorrent-ipfilter-update.service" ];
        after = [ "qbittorrent-ipfilter-update.service" ];
      };
    })
  ]);
}
