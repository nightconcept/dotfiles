# Mount the Titan SMB share (served by Mog) at ~/titan on macOS.
#
# Reuses the same SOPS secret as the Linux hosts (network/titan_credentials in
# modules/nixos/security/sops/common.yaml), which holds username/domain/password
# lines. A launchd agent runs at login and every few minutes: it exits at once if
# the share is mounted or Mog is unreachable, so it also remounts after sleep or
# a network change.
{
  config,
  lib,
  pkgs,
  ...
}: let
  moduleLib = import ../../../lib/module {inherit lib;};
  inherit (moduleLib) mkBoolOpt;

  cfg = config.modules.home.programs.titanMount;
  home = config.home.homeDirectory;
  mountPoint = "${home}/titan";
  credentials = "${home}/.local/share/sops/secrets/titan_credentials";

  mountScript = pkgs.writeShellScript "titan-mount" ''
    set -eu
    export PATH=${lib.makeBinPath [pkgs.jq pkgs.coreutils pkgs.gnused]}:/usr/bin:/sbin:/bin

    if /sbin/mount | grep -q " on ${mountPoint} (smbfs"; then
      exit 0
    fi
    if ! /usr/bin/nc -z -G 3 ${cfg.server} 445 >/dev/null 2>&1; then
      echo "Mog (${cfg.server}) is unreachable; will retry"
      exit 0
    fi
    if [ ! -s ${credentials} ]; then
      echo "Credentials ${credentials} not deployed yet; will retry"
      exit 0
    fi

    field() { sed -n "s/^$1=//p" ${credentials} | head -1; }
    enc() { printf '%s' "$1" | jq -sRr @uri; }
    user=$(enc "$(field username)")
    domain=$(enc "$(field domain)")
    pass=$(enc "$(field password)")

    mkdir -p ${mountPoint}
    # Password is only on this process's argv for the duration of the mount call.
    exec /sbin/mount_smbfs "//$domain;$user:$pass@${cfg.server}/${cfg.share}" ${mountPoint}
  '';
in {
  options.modules.home.programs.titanMount = {
    enable = mkBoolOpt false "Mount the Titan SMB share at ~/titan (macOS)";
    server = lib.mkOption {
      type = lib.types.str;
      default = "192.168.1.167";
      description = "Mog's LAN address.";
    };
    share = lib.mkOption {
      type = lib.types.str;
      default = "titan";
      description = "SMB share name.";
    };
  };

  config = lib.mkIf (cfg.enable && pkgs.stdenv.hostPlatform.isDarwin) {
    sops.secrets.titan_credentials = {
      sopsFile = ../../nixos/security/sops/common.yaml;
      key = "network/titan_credentials";
      path = credentials;
      mode = "0400";
    };

    launchd.agents.titan-mount = {
      enable = true;
      config = {
        ProgramArguments = ["${mountScript}"];
        RunAtLoad = true;
        StartInterval = 300;
        StandardOutPath = "${home}/Library/Logs/titan-mount.log";
        StandardErrorPath = "${home}/Library/Logs/titan-mount.log";
      };
    };
  };
}
