{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  inherit (lib) mkIf mkMerge;
  cfg = config.modules.nixos.services.nordvpn;

  # Import our custom lib functions
  moduleLib = import ../../../../lib/module { inherit lib; };
  inherit (moduleLib) mkBoolOpt mkOpt enabled disabled;

  # Use the nordvpn package from the flake
  nordVpnPkg = inputs.nordvpn-flake.packages.${pkgs.system}.default;
in
{
  options.modules.nixos.services.nordvpn = {
    enable = mkBoolOpt false "Enable the NordVPN daemon and CLI client from nordvpn-flake";

    user = mkOpt lib.types.str "danny" "User to add to nordvpn group";

    tokenFile = mkOpt (lib.types.nullOr lib.types.path) null "Path to NordVPN token file (managed via SOPS)";

    killSwitch = mkBoolOpt true "Enable kill switch (block internet if VPN disconnects)";

    autoConnect = mkBoolOpt true "Automatically connect to VPN on boot";

    server = mkOpt (lib.types.nullOr lib.types.str) null "Specific server to connect to (null = auto P2P for torrenting)";

    protocol = mkOpt lib.types.str "NordLynx" "VPN protocol to use (NordLynx, OpenVPN)";

    dns = mkOpt (lib.types.listOf lib.types.str) ["103.86.96.100" "103.86.99.100"] "Custom DNS servers";
  };

  config = mkIf cfg.enable {
    # Required firewall configuration for NordVPN
    networking.firewall = {
      checkReversePath = "loose";  # Required for NordVPN
      allowedTCPPorts = [ 443 ];
      allowedUDPPorts = [ 1194 ];
    };

    # Install NordVPN package from flake
    environment.systemPackages = [ nordVpnPkg ];

    # Create nordvpn group and add user
    users.groups.nordvpn = {};
    users.users.${cfg.user}.extraGroups = [ "nordvpn" ];

    # NordVPN daemon service
    systemd.services.nordvpn = {
      description = "NordVPN daemon";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        ExecStart = "${nordVpnPkg}/bin/nordvpnd";
        NonBlocking = true;
        KillMode = "process";
        Restart = "on-failure";
        RestartSec = 5;
        RuntimeDirectory = "nordvpn";
        RuntimeDirectoryMode = "0750";
        Group = "nordvpn";

        # Create socket directory with proper permissions
        ExecStartPre = pkgs.writeShellScript "nordvpn-prestart" ''
          mkdir -p /run/nordvpn
          chown root:nordvpn /run/nordvpn
          chmod 0750 /run/nordvpn
        '';
      };
    };

    # Post-start configuration service
    systemd.services.nordvpn-configure = mkIf (cfg.tokenFile != null) {
      description = "Configure NordVPN settings";
      after = [ "nordvpn.service" ];
      wants = [ "nordvpn.service" ];
      wantedBy = [ "multi-user.target" ];

      script = ''
        # Wait for daemon to be ready
        while ! ${nordVpnPkg}/bin/nordvpn status >/dev/null 2>&1; do
          echo "Waiting for NordVPN daemon..."
          sleep 2
        done

        # Login with token if not already logged in
        if ! ${nordVpnPkg}/bin/nordvpn account >/dev/null 2>&1; then
          if [ -f "${cfg.tokenFile}" ]; then
            echo "Logging in with NordVPN token..."
            TOKEN=$(cat "${cfg.tokenFile}")
            ${nordVpnPkg}/bin/nordvpn login --token "$TOKEN"
          else
            echo "Warning: NordVPN token file not found at ${cfg.tokenFile}"
            exit 1
          fi
        fi

        # Configure settings
        echo "Configuring NordVPN settings..."

        # Enable LAN discovery to allow local network access
        ${nordVpnPkg}/bin/nordvpn set lan-discovery enable

        # Configure kill switch
        ${lib.optionalString cfg.killSwitch ''
          ${nordVpnPkg}/bin/nordvpn set killswitch on
        ''}
        ${lib.optionalString (!cfg.killSwitch) ''
          ${nordVpnPkg}/bin/nordvpn set killswitch off
        ''}

        # Set VPN technology (NordLynx or OpenVPN)
        ${nordVpnPkg}/bin/nordvpn set technology ${cfg.protocol}

        # Configure custom DNS servers
        ${lib.optionalString (cfg.dns != []) ''
          ${nordVpnPkg}/bin/nordvpn set dns ${lib.concatStringsSep " " cfg.dns}
        ''}

        # Configure autoconnect with P2P server preference
        ${lib.optionalString cfg.autoConnect ''
          ${lib.optionalString (cfg.server != null) ''
            # Connect to specific server with autoconnect
            ${nordVpnPkg}/bin/nordvpn set autoconnect on ${cfg.server}
          ''}
          ${lib.optionalString (cfg.server == null) ''
            # Connect to P2P server for torrenting
            ${nordVpnPkg}/bin/nordvpn set autoconnect on
            echo "Connecting to P2P server for torrenting..."
            ${nordVpnPkg}/bin/nordvpn connect p2p
          ''}
        ''}
        ${lib.optionalString (!cfg.autoConnect) ''
          ${nordVpnPkg}/bin/nordvpn set autoconnect off
        ''}

        # Connect to specified server if autoconnect is disabled but server is specified
        ${lib.optionalString (!cfg.autoConnect && cfg.server != null) ''
          echo "Connecting to ${cfg.server}..."
          ${nordVpnPkg}/bin/nordvpn connect ${cfg.server}
        ''}

        # If no specific server but autoconnect disabled, connect to P2P
        ${lib.optionalString (!cfg.autoConnect && cfg.server == null) ''
          echo "Connecting to P2P server for torrenting..."
          ${nordVpnPkg}/bin/nordvpn connect p2p
        ''}

        # Show final status
        echo "NordVPN configuration applied. Checking status..."
        ${nordVpnPkg}/bin/nordvpn status || true
        ${nordVpnPkg}/bin/nordvpn settings || true

        echo "NordVPN configuration complete"
      '';

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # Run as root for system configuration but token is readable by danny
        User = "root";
        Group = "nordvpn";
      };
    };
  };
}