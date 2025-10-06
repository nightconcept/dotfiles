# OpenSSH server configuration module
{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.modules.nixos.services.openssh;
in {
  options.modules.nixos.services.openssh = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable OpenSSH server with secure defaults";
    };

    port = mkOption {
      type = types.int;
      default = 22;
      description = "SSH port";
    };

    permitRootLogin = mkOption {
      type = types.str;
      default = "no";
      description = "Whether to permit root login";
    };

    passwordAuthentication = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to allow password authentication";
    };
  };

  config = mkIf cfg.enable {
    services.openssh = {
      enable = true;
      ports = [cfg.port];

      settings = {
        # Security hardening
        PermitRootLogin = cfg.permitRootLogin;
        PasswordAuthentication = cfg.passwordAuthentication;
        KbdInteractiveAuthentication = false;

        # Enable both key and password authentication (keys preferred)
        PubkeyAuthentication = true;

        # Disable unused authentication methods
        ChallengeResponseAuthentication = false;
        UsePAM = true; # Required for password authentication

        # Connection limits
        MaxAuthTries = 3;
        ClientAliveInterval = 60;
        ClientAliveCountMax = 3;

        # Protocol settings
        Protocol = 2;
        X11Forwarding = false;
        AllowTcpForwarding = "yes";
        GatewayPorts = "no";

        # Logging
        LogLevel = "INFO";
      };

      # Open firewall for SSH
      openFirewall = true;
    };
  };
}
