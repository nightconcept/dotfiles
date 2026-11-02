{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.nixos.docker.containers.finance;
  containerPath = "/var/lib/docker-containers/finance";
  ledgerPath = "/home/danny/git/ledger";
  misePackage = pkgs.callPackage ../../../../../../pkgs/mise/package.nix {};
  syncService = description: command: {
    inherit description;
    after = ["docker-container-finance.service" "network-online.target"];
    requires = ["docker-container-finance.service"];
    wants = ["network-online.target"];
    path = [pkgs.bash pkgs.git pkgs.openssh pkgs.uv misePackage pkgs.sops pkgs.ssh-to-age];
    serviceConfig = {
      Type = "oneshot";
      User = "danny";
      WorkingDirectory = ledgerPath;
      UMask = "0077";
      Environment = [
        "UV_PYTHON=${pkgs.python313}/bin/python3"
        "UV_PYTHON_DOWNLOADS=never"
        "MISE_AUTO_INSTALL=0"
      ];
      ExecStart = "${misePackage}/bin/mise exec -- ${pkgs.bash}/bin/bash -c ${lib.escapeShellArg command}";
    };
  };
in {
  options.modules.nixos.docker.containers.finance.enable =
    lib.mkEnableOption "Actual Budget and Paisa behind Traefik";

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${containerPath} 0700 root root -"
      "d /home/danny/docker/actual 0700 danny users -"
      "d /home/danny/docker/paisa 0700 danny users -"
    ];

    systemd.services.docker-container-finance = {
      description = "Actual Budget and Paisa";
      after = ["docker.service" "docker-network-proxy.service"];
      requires = ["docker.service" "docker-network-proxy.service"];
      wantedBy = ["multi-user.target"];
      preStart = ''
        # Refuse to create empty replacement databases before migration.
        test -d /home/danny/docker/actual/data/server-files
        test -f /home/danny/docker/paisa/data/paisa.yaml
        test -f ${ledgerPath}/ledger/main.journal
        cp ${./docker-compose.yml} ${containerPath}/docker-compose.yml
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

    systemd.services.ledger-sync =
      syncService
      "Regenerate hledger journal from Actual Budget"
      "uv run --frozen ledger-tool sync && git push";
    systemd.services.ledger-sync-house =
      syncService
      "Snapshot house valuation into hledger"
      ''uv run --frozen ledger-tool sync --house --apply && git add -- ledger/prices.journal && (git diff --cached --quiet -- ledger/prices.journal || git commit --no-verify -m "chore: sync house valuation" -- ledger/prices.journal) && git push'';

    systemd.timers = {
      ledger-sync = {
        wantedBy = ["timers.target"];
        timerConfig = {
          OnCalendar = "*-*-* 06:00:00";
          Persistent = true;
        };
      };
      ledger-sync-house = {
        wantedBy = ["timers.target"];
        timerConfig = {
          OnCalendar = "*-*-01 07:00:00";
          Persistent = true;
        };
      };
    };
  };
}
