{
  config,
  lib,
  pkgs,
  ...
}: let
  # Import our custom lib functions
  moduleLib = import ../../../lib/module {inherit lib;};
  inherit (moduleLib) mkBoolOpt enabled disabled;
in {
  options.modules.home.secrets.sops = {
    enable = mkBoolOpt true "Enable SOPS secrets management for home-manager";
  };

  config = lib.mkIf config.modules.home.secrets.sops.enable {
    # SOPS configuration for home-manager (works on all platforms)
    sops = {
      # Use the user's age key (converted from SSH key)
      age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";

      # Default secrets file
      defaultSopsFile = ./user.yaml;

      # Validate files
      validateSopsFiles = true;

      # User-level secrets
      secrets = {
        # Forgejo git personal access token
        "forgejo_git_token" = {
          path = "${config.home.homeDirectory}/.local/share/sops/secrets/forgejo_git_token";
          mode = "0400";
        };

        # Brave Search API key for Claude Code MCP
        "brave_api_key" = {
          # Use XDG runtime dir for better security (tmpfs, user-only access)
          path = "%r/secrets/brave_api_key";
          mode = "0400";
        };

        # Context7 API key for Claude Code MCP (library docs)
        "context7_api_key" = {
          # Use XDG runtime dir for better security (tmpfs, user-only access)
          path = "%r/secrets/context7_api_key";
          mode = "0400";
        };

        # Ollama cloud API key for pi agent (GLM-5.1, DeepSeek V4 Pro cloud models)
        "ollama_api_key" = {
          path = "${config.home.homeDirectory}/.local/share/sops/secrets/ollama_api_key";
          mode = "0400";
        };

        # Other user secrets can be added here
      };
    };

    # Ensure the age keys directory exists
    home.file.".config/sops/age/.keep".text = "";

    # Fallback activation for environments without systemd user session (e.g., WSL2)
    # This ensures secrets are deployed even when systemctl --user doesn't work
    home.activation.sops-nix-fallback = lib.hm.dag.entryAfter ["writeBoundary"] ''
      # Check if systemd user session is running
      if ! systemctl --user is-system-running >/dev/null 2>&1; then
        $VERBOSE_ECHO "Systemd user session not available, running sops-nix activation directly"

        # Find the sops-nix activation script
        SOPS_SCRIPT=$(readlink -f ~/.config/systemd/user/sops-nix.service 2>/dev/null | xargs grep -oP 'ExecStart=\K.*' 2>/dev/null || true)

        if [ -n "$SOPS_SCRIPT" ] && [ -x "$SOPS_SCRIPT" ]; then
          $VERBOSE_ECHO "Running: $SOPS_SCRIPT"
          "$SOPS_SCRIPT" || $VERBOSE_ECHO "Warning: sops-nix activation failed"
        else
          $VERBOSE_ECHO "Warning: Could not find sops-nix activation script"
        fi
      fi
    '';

    # WSL workaround: Auto-deploy secrets on shell login if tmpfs was cleared
    # Since /run/user/$UID is tmpfs and cleared on reboot, and systemd --user
    # doesn't work in WSL, we need to re-deploy secrets on every new shell

    # Create a shell script that auto-deploys secrets
    home.file.".config/sops-nix/auto-deploy.sh" = {
      text = ''
        #!/usr/bin/env bash
        # Auto-deploy sops secrets if missing (WSL tmpfs workaround)
        if [ ! -f ~/.local/share/sops/secrets/forgejo_git_token ]; then
          SOPS_SCRIPT=$(readlink -f ~/.config/systemd/user/sops-nix.service 2>/dev/null | xargs grep -oP 'ExecStart=\K.*' 2>/dev/null || true)
          if [ -n "$SOPS_SCRIPT" ] && [ -x "$SOPS_SCRIPT" ]; then
            "$SOPS_SCRIPT" >/dev/null 2>&1 || true
          fi
        fi
      '';
      executable = true;
    };

    # Source the auto-deploy script in bash profile (works even if bashrc isn't managed)
    home.file.".bash_profile" = {
      text = ''
        #
        # ~/.bash_profile
        #

        [[ -f ~/.bashrc ]] && . ~/.bashrc

        # Auto-deploy sops-nix secrets on login (WSL workaround)
        [ -f ~/.config/sops-nix/auto-deploy.sh ] && source ~/.config/sops-nix/auto-deploy.sh

        # Launch fish for interactive sessions; non-interactive (VS Code SSH, scripts) stays bash
        [[ $- == *i* ]] && exec fish
      '';
      force = true; # Overwrite existing file
    };

    # For Fish: Use the proper config option
    programs.fish.interactiveShellInit = ''
      # Auto-deploy sops secrets if missing (WSL tmpfs workaround)
      if not test -f ~/.local/share/sops/secrets/forgejo_git_token
        set -l sops_script (readlink -f ~/.config/systemd/user/sops-nix.service 2>/dev/null | xargs grep -oP 'ExecStart=\K.*' 2>/dev/null; or echo "")
        if test -n "$sops_script" && test -x "$sops_script"
          $sops_script >/dev/null 2>&1; or true
        end
      end
    '';
  };
}
