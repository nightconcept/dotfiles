# User configuration module
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.modules.nixos.core.users;
in {
  options.modules.nixos.core.users = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable user configuration";
    };

    primaryUser = mkOption {
      type = types.str;
      default = "danny";
      description = "Primary user name";
    };
  };

  config = mkIf cfg.enable {
    users.users.${cfg.primaryUser} = {
      isNormalUser = true;
      description = "Danny";
      extraGroups = ["networkmanager" "wheel" "docker" "libvirtd" "video" "audio"];
      shell = pkgs.fish;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMJKTm63zFmYfGauCBlUWq7lvHFq+NVPT5RqIfjLM7MN danny@solivan.dev"
      ];
    };

    programs.fish.enable = true;
  };
}
