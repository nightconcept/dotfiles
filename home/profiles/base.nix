# Base configuration shared across all machines
{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [
    ../../modules/home
  ];

  modules.home = {
    programs = {
      claude-code = {
        enable = true;
        # Enable statusline with settings management
        statusline = {
          enable = true;
          manageSettings = true;
        };
        # Enable MCP servers that don't require API keys by default
        mcp = {
          sequential-thinking.enable = true;
          filesystem.enable = true;
          fetch.enable = true;
          # API keys are managed via SOPS secrets
          brave-search.enable = true;
          context7.enable = true;
        };
      };
      common.enable = true;
      direnv.enable = true;
      git.enable = true;
      nvim = {
        enable = true;
        distro = "nvchad";
      };
      ssh.enable = true;
    };
    secrets = {
      sops.enable = true;
    };
  };

  home = {
    username = lib.mkDefault (let envUser = builtins.getEnv "USER"; in if envUser != "" then envUser else "danny");
    homeDirectory = lib.mkDefault (
      let envHome = builtins.getEnv "HOME";
      in if envHome != "" then envHome else "/home/danny"
    );
    stateVersion = "23.11";

    # Essential system packages
    packages = with pkgs; [
      openssh  # Needed for git commit signing with SSH keys
      kondo
    ];
  };

  programs.home-manager.enable = true;

  manual.manpages.enable = false;

  news.display = "silent";
}
