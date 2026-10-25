{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.nixos.docker.containers.security-stack;
  central = cfg.role == "central";
  runtime = "/var/lib/docker-containers/security-stack";
  python = pkgs.python3.withPackages (ps: [ps.pyyaml ps.bcrypt]);
  upstream = pkgs.fetchzip {
    url = "https://codeload.github.com/wazuh/wazuh-docker/tar.gz/refs/tags/v4.14.5";
    extension = "tar.gz";
    hash = "sha256-aFWA1tdkjRnWFyeNf404Hqg+MDl7hhuf34hFsxbMaRY=";
  };
  runtimeFiles = [
    "prepare.py"
    "maintain.py"
    "gotify_bridge.py"
    "compose.base.yml"
    "evebox.yaml"
    "suricata-logrotate"
    "test_prepare.py"
    "test_maintain.py"
    "test_gotify_bridge.py"
  ];
  runtimePackage = pkgs.runCommand "security-stack-runtime" {nativeBuildInputs = [pkgs.openssl];} ''
    mkdir -p "$out"
    ${lib.concatMapStringsSep "\n" (name: "cp ${./. + "/${name}"} \"$out/${name}\"") runtimeFiles}
    ln -s ${upstream}/single-node "$out/wazuh"
    PYTHONDONTWRITEBYTECODE=1 ${python}/bin/python -m unittest discover -s "$out" -p 'test_*.py'
  '';
  settings = pkgs.writeText "security-stack-settings.json" (builtins.toJSON {
    inherit (cfg) role interfaces captureInterfaces serverAddress listenAddress retentionDays sensors eveboxUrl;
    hostname = config.networking.hostName;
    gotifyUrl = "http://192.168.1.185:8070";
    inherit (cfg) gotifyTokenFile;
  });
  services =
    ["suricata" "evebox-gotify"]
    ++ (
      if central
      then ["evebox" "wazuh-manager" "wazuh-indexer" "wazuh-dashboard"]
      else ["evebox-agent" "wazuh-agent"]
    );
in {
  options.modules.nixos.docker.containers.security-stack = {
    enable = lib.mkEnableOption "distributed Suricata, EveBox and Wazuh security stack";
    package = lib.mkOption {
      type = lib.types.package;
      default = runtimePackage;
      readOnly = true;
      description = "Checked runtime scripts and pinned Wazuh configuration.";
    };
    role = lib.mkOption {
      type = lib.types.enum ["central" "sensor"];
      default = "sensor";
      description = "Central analysis services or local sensor and event forwarders.";
    };
    interfaces = lib.mkOption {
      type = lib.types.listOf (lib.types.strMatching "[A-Za-z0-9_.:-]+");
      default = ["ens18"];
      description = "Guest interfaces visible to Suricata; add verified mirror NICs here.";
    };
    captureInterfaces = lib.mkOption {
      type = lib.types.listOf (lib.types.strMatching "[A-Za-z0-9_.:-]+");
      default = [];
      description = "Verified mirror NICs to keep addressless and unmanaged by NetworkManager.";
    };
    serverAddress = lib.mkOption {
      type = lib.types.str;
      default = "192.168.1.185";
      description = "Central server IPv4 address for agent transport and certificate SANs.";
    };
    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = cfg.serverAddress;
      description = "Trusted host address on which central interfaces and enrollment listen.";
    };
    eveboxUrl = lib.mkOption {
      type = lib.types.strMatching "https://.+";
      default = "https://evebox.local.solivan.dev";
      description = "Authenticated HTTPS EveBox endpoint for remote sensors.";
    };
    sensors = lib.mkOption {
      type = lib.types.listOf (lib.types.strMatching "[A-Za-z0-9_-]+");
      default = [];
      description = "Sensor identities for which the central role exports enrollment files.";
    };
    retentionDays = lib.mkOption {
      type = lib.types.ints.between 1 30;
      default = 3;
      description = "Retention for EveBox events and dated Wazuh alert indices and logs.";
    };
    gotifyTokenFile = lib.mkOption {
      type = lib.types.str;
      default = "/run/secrets/security-stack-gotify-token";
      description = "Runtime Gotify application token file; never copied into the Nix store.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.all (interface: lib.elem interface cfg.interfaces) cfg.captureInterfaces;
        message = "security-stack.captureInterfaces must be included in interfaces";
      }
      {
        assertion = !central || lib.toInt (toString config.boot.kernel.sysctl."vm.max_map_count") >= 262144;
        message = "security-stack central role requires vm.max_map_count >= 262144";
      }
      {
        assertion = cfg.interfaces != [];
        message = "security-stack.interfaces must not be empty";
      }
      {
        assertion = config.modules.nixos.security.sops.enable;
        message = "security-stack requires SOPS for its notification token";
      }
    ];
    virtualisation.docker.enable = true;
    networking.networkmanager.unmanaged = map (interface: "interface-name:${interface}") cfg.captureInterfaces;
    networking.interfaces = lib.genAttrs cfg.captureInterfaces (_: {useDHCP = false;});
    sops.secrets.security-stack-gotify-token = {
      sopsFile = ../../../../security/sops/suricata.yaml;
      key = "gotify_token";
      mode = "0400";
    };
    systemd.tmpfiles.rules = ["d ${runtime} 0700 root root -"];
    systemd.services.docker-container-security-stack = {
      description = "Distributed security stack (${cfg.role})";
      wantedBy = ["multi-user.target"];
      after = ["docker.service" "network-online.target" "sops-install-secrets.service"];
      requires = ["docker.service" "sops-install-secrets.service"];
      wants = ["network-online.target"];
      path = [pkgs.docker pkgs.docker-compose pkgs.openssl pkgs.iproute2 pkgs.procps];
      preStart = ''
        test -s ${lib.escapeShellArg cfg.gotifyTokenFile}
        ${python}/bin/python ${cfg.package}/prepare.py ${settings} ${cfg.package}/wazuh ${runtime}
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        WorkingDirectory = runtime;
        UMask = "0077";
        TimeoutStartSec = "20min";
        ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d --wait --wait-timeout 600";
        ExecStop = "${pkgs.docker-compose}/bin/docker-compose down";
      };
    };
    systemd.services.security-stack-maintenance = {
      description = "Update security rules, rotate logs and expire old events";
      after = ["docker-container-security-stack.service"];
      requires = ["docker-container-security-stack.service"];
      path = [pkgs.docker pkgs.docker-compose];
      serviceConfig = {
        Type = "oneshot";
        WorkingDirectory = runtime;
      };
      script = ''
        ${python}/bin/python ${cfg.package}/maintain.py ${settings} ${runtime}
      '';
    };
    systemd.timers.security-stack-maintenance = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "hourly";
        RandomizedDelaySec = "5min";
        Persistent = true;
      };
    };
    modules.nixos.docker.healthCheck.expectedContainers = map (name: "security-stack-${name}") services;
    modules.nixos.docker.healthCheck.afterUnits = ["docker-container-security-stack.service"];
  };
}
