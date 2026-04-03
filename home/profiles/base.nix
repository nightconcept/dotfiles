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
      gemini-cli.enable = true; # Uses bin version by default
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
    username = lib.mkDefault (builtins.getEnv "USER");
    homeDirectory = lib.mkDefault (builtins.getEnv "HOME");
    stateVersion = "23.11";

    # Essential system packages
    packages = with pkgs; [
      openssh  # Needed for git commit signing with SSH keys
    ];
  };

  programs.home-manager.enable = true;

  news.display = "silent";
}
