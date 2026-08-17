# SOPS secrets management module
{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.modules.nixos.security.sops;
in {
  options.modules.nixos.security.sops = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable SOPS secret management";
    };
  };

  config = mkIf cfg.enable {
    # Ensure /run/secrets doesn't exist before SOPS runs
    # This prevents conflicts where something creates it as a regular directory
    system.activationScripts.cleanupSecretsBeforeSops = {
      text = ''
        # Remove any existing /run/secrets directory that might interfere with SOPS
        if [ -e /run/secrets ] && [ ! -L /run/secrets ]; then
          echo "Removing existing /run/secrets directory to allow SOPS to create its symlink"
          rm -rf /run/secrets
        fi
        # Also clean up any leftover temp directories
        rm -rf /run/.secrets-temp 2>/dev/null || true
      '';
      # Run before setupSecrets (SOPS)
      deps = [];
    };

    sops = {
      defaultSopsFile = ./common.yaml;
      defaultSopsFormat = "yaml";

      # Secrets live in /run and must be re-created on every boot.  Use the
      # systemd unit rather than the switch-only activation script so services
      # can reliably depend on them.
      useSystemdActivation = true;

      # IMPORTANT: System-level SOPS requires an age key at boot time
      # The key must be placed at /var/lib/sops-nix/key.txt
      # This is handled by the bootstrap script during installation
      # For existing systems, run: sudo mkdir -p /var/lib/sops-nix && echo "AGE_KEY" | sudo tee /var/lib/sops-nix/key.txt
      age.keyFile = "/var/lib/sops-nix/key.txt";

      # Fallback to SSH host keys if age key is not available
      age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];

      secrets = {
        "ssh_keys/id_sdev" = {
          owner = "danny";
          path = "/home/danny/.ssh/id_sdev";
          mode = "0600";
        };
        "network/titan_credentials" = {
          owner = "root";
          mode = "0400";
        };
        "vpn/nordvpn_token" = {
          # SOPS will handle the path automatically
          owner = "root";
          mode = "0400";
        };
        "vpn/qbittorrent_password" = {
          # SOPS will handle the path automatically
          owner = "danny";
          mode = "0400";
        };
        "vpn/qbittorrent_password_hash" = {
          # PBKDF2 hash for qBittorrent WebUI authentication
          owner = "danny";
          mode = "0400";
        };
        "forgejo_runner_token" = {
          owner = "root";
          mode = "0400";
        };

        # Docker container service secrets
        "services/traefik/cloudflare_token" = {
          owner = "root";
          mode = "0400";
        };

        "services/ddclient/password" = {
          owner = "root";
          mode = "0400";
        };

        "services/watchtower/api_token" = {
          owner = "root";
          mode = "0400";
        };

        "services/cloudflare-tunnel/tunnel_token" = {
          owner = "root";
          mode = "0400";
        };

        "services/vaultwarden/admin_token" = {
          owner = "root";
          mode = "0400";
        };

        "services/nextcloud/db_root_password" = {
          owner = "root";
          mode = "0400";
        };
        "services/nextcloud/db_password" = {
          owner = "root";
          mode = "0400";
        };
        "services/nextcloud/collabora_password" = {
          owner = "root";
          mode = "0400";
        };
        "services/nextcloud/jwt_secret" = {
          owner = "root";
          mode = "0400";
        };

        "services/immich/db_password" = {
          owner = "root";
          mode = "0400";
        };

        "services/crowdsec/bouncer_key" = {
          owner = "root";
          mode = "0400";
        };
        "services/crowdsec/enroll_key" = {
          owner = "root";
          mode = "0400";
        };

        "services/zotero/username" = {
          owner = "root";
          mode = "0400";
        };
        "services/zotero/password" = {
          owner = "root";
          mode = "0400";
        };
      };
    };
  };
}
