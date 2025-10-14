{
  config,
  lib,
  pkgs,
  ...
}: let
  # Import our custom lib functions
  moduleLib = import ../../../../lib/module {inherit lib;};
  inherit (moduleLib) mkBoolOpt enabled disabled;

  # Dotfiles directory constant - change this if the repo moves
  dot_dir = "$HOME/git/dotfiles";
in {
  options.modules.home.programs.shell.fish = {
    enable = mkBoolOpt false "Enable Fish shell";
  };

  config = lib.mkIf config.modules.home.programs.shell.fish.enable {
    home.sessionPath =
      [
        "/home/danny/.local/bin"
        "/opt/nvim-linux64/bin"
      ]
      ++ (
        if pkgs.stdenv.isDarwin
        then [
          "/usr/local/bin"
          "/opt/homebrew/bin"
          "/Users/danny/.local/bin"
        ]
        else []
      );

    programs.fish = {
      enable = true;

      shellAliases =
        {
          # Git aliases
          gs = "${pkgs.git}/bin/git status -sb";
          gcm = "${pkgs.git}/bin/git checkout master";
          gaa = "${pkgs.git}/bin/git add --all";
          gc = "${pkgs.git}/bin/git commit -m";
          push = "${pkgs.git}/bin/git push";
          gpo = "${pkgs.git}/bin/git push origin";
          pull = "${pkgs.git}/bin/git pull";
          clone = "${pkgs.git}/bin/git clone";
          stash = "${pkgs.git}/bin/git stash";
          pop = "${pkgs.git}/bin/git stash pop";
          ga = "${pkgs.git}/bin/git add";
          gb = "${pkgs.git}/bin/git branch";
          gl = "${pkgs.git}/bin/git log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";
          gm = "${pkgs.git}/bin/git merge";
          gdev = "${pkgs.git}/bin/git checkout main && ${pkgs.git}/bin/git fetch origin --prune && ${pkgs.git}/bin/git reset --hard origin/main && ${pkgs.git}/bin/git branch dev && ${pkgs.git}/bin/git checkout dev && ${pkgs.git}/bin/git reset --hard main && ${pkgs.git}/bin/git push origin dev --force";

          # Editor alias
          e = "$EDITOR";

          # General aliases
          "." = "z .";
          ".." = "z ..";
          "..." = "z ../../";
          "...." = "z ../../../";
          "....." = "z ../../../../";
          cd = "z";
          cls = "clear";
          ls = "${pkgs.eza}/bin/eza -F --color=auto";
          ll = "${pkgs.eza}/bin/eza -l";
          "ll." = "${pkgs.eza}/bin/eza -la";
          lls = "${pkgs.eza}/bin/eza -la --sort=size";
          llt = "${pkgs.eza}/bin/eza -la --sort=time";
          cat = "${pkgs.bat}/bin/bat";
          rm = "${pkgs.coreutils}/bin/rm -iv";
          mkdir = "${pkgs.coreutils}/bin/mkdir -p";
          cp = "${pkgs.coreutils}/bin/cp -r";
          fishclear = "echo \"\" > ~/.local/share/fish/fish_history";
        }
        // (
          if pkgs.stdenv.isLinux
          then {
            apt = "sudo apt";
          }
          else {}
        );

      shellInit = ''
        # Set environment variables
        set -gx EDITOR nvim
        set -gx BROWSER firefox
        set -gx TERMINAL wezterm
        set -gx LANG en_US.UTF-8
        set -gx VISUAL nvim
        set -gx GPG_TTY (tty)
        ${
          if pkgs.stdenv.isDarwin
          then ''
            set -gx XDG_DATA_DIRS /Users/danny/.nix-profile/share $XDG_DATA_DIRS
          ''
          else ''
            set -gx XDG_DATA_DIRS /home/danny/.nix-profile/share $XDG_DATA_DIRS

            # Auto-start nix-daemon on WSL when systemd is not available
            # Check if we're on WSL and systemd is NOT running (e.g., Gentoo with OpenRC)
            if test -f /proc/version; and string match -q -r -i microsoft (cat /proc/version)
                # Only manually start nix-daemon if systemd isn't managing it
                if not test -d /run/systemd/system
                    if not pgrep -x nix-daemon > /dev/null 2>&1
                        sudo /nix/var/nix/profiles/default/bin/nix-daemon > /dev/null 2>&1 &
                    end
                end
            end
          ''
        }

        # Ensure Nix is in PATH
        if test -d "/nix/var/nix/profiles/default/bin"
            fish_add_path --prepend /nix/var/nix/profiles/default/bin
        end
        ${
          if pkgs.stdenv.isDarwin
          then ''
            if test -d "/Users/danny/.nix-profile/bin"
                fish_add_path --prepend /Users/danny/.nix-profile/bin
            end
            if test -d "/etc/profiles/per-user/danny/bin"
                fish_add_path --prepend /etc/profiles/per-user/danny/bin
            end
            if test -d "/run/current-system/sw/bin"
                fish_add_path --prepend /run/current-system/sw/bin
            end
          ''
          else ''
            if test -d "/home/danny/.nix-profile/home-path/bin"
                fish_add_path --prepend /home/danny/.nix-profile/home-path/bin
            end
            if test -d "/home/danny/.nix-profile/bin"
                fish_add_path --prepend /home/danny/.nix-profile/bin
            end
          ''
        }

        # Load API keys from sops if available
        if test -r "$XDG_RUNTIME_DIR/secrets/gemini_api_key"
            set -gx GEMINI_API_KEY (cat "$XDG_RUNTIME_DIR/secrets/gemini_api_key")
        end

        # Conditional brew setup
        if test -d "/home/linuxbrew/"
            eval (/home/linuxbrew/.linuxbrew/bin/brew shellenv)
        end

        # UV tool path setup
        if test -d "/home/danny/.local/share/uv/tools"
            for tool_dir in /home/danny/.local/share/uv/tools/*/bin
                if test -d "$tool_dir"
                    fish_add_path --prepend "$tool_dir"
                end
            end
        end

        # NPM global bin path for claude-sandbox
        if test -d "/home/danny/.npm-global/bin"
            fish_add_path --prepend /home/danny/.npm-global/bin
        end
      '';

      plugins = [
        {
          name = "tide";
          src = pkgs.fishPlugins.tide.src;
        }
        {
          name = "done";
          src = pkgs.fishPlugins.done.src;
        }
        {
          name = "fzf-fish";
          src = pkgs.fishPlugins.fzf-fish.src;
        }
        {
          name = "autopair";
          src = pkgs.fishPlugins.autopair.src;
        }
        {
          name = "sponge";
          src = pkgs.fishPlugins.sponge.src;
        }
      ];

      functions = {
        fish_greeting = {
          description = "Greeting to show when starting a fish shell";
          body = "";
        };

        flake-rebuild = {
          description = "Smart flake rebuild that auto-detects system and hostname";
          body = ''
            # Parse arguments - check if host was provided
            if test (count $argv) -gt 0
                set host $argv[1]
                echo "Using specified host: $host"
            else
                # Auto-detect hostname
                set host (hostname -s)
                echo "Auto-detected host: $host"
            end

            # Determine flake directory
            if set -q FLAKE_DIR
                set flake_dir $FLAKE_DIR
            else
                set flake_dir "${dot_dir}"
            end

            # Verify flake directory exists
            if not test -d $flake_dir
                echo "Error: Flake directory not found at $flake_dir"
                echo "Set FLAKE_DIR environment variable or ensure ${dot_dir} exists"
                return 1
            end

            # Check what configurations are available in the flake for this hostname
            set nixos_configs (nix eval $flake_dir#nixosConfigurations --apply 'x: builtins.attrNames x' 2>/dev/null | tr -d '[]"' | tr ' ' '\n')
            set darwin_configs (nix eval $flake_dir#darwinConfigurations --apply 'x: builtins.attrNames x' 2>/dev/null | tr -d '[]"' | tr ' ' '\n')
            set home_configs (nix eval $flake_dir#homeConfigurations --apply 'x: builtins.attrNames x' 2>/dev/null | tr -d '[]"' | tr ' ' '\n')

            # Check if hostname exists in any configuration type
            if contains $host $nixos_configs
                echo "Found NixOS configuration for $host"
                set config_type "nixosConfigurations"
                set rebuild_cmd "sudo nixos-rebuild switch"
            else if contains $host $darwin_configs
                echo "Found Darwin configuration for $host"
                set config_type "darwinConfigurations"
                set rebuild_cmd "sudo darwin-rebuild switch"
            else if contains $host $home_configs
                echo "Found Home Manager configuration for $host"
                set config_type "homeConfigurations"
                set rebuild_cmd "home-manager switch"
            else
                # Try user@host format for home-manager
                set user_host "danny@$host"
                if contains $user_host $home_configs
                    echo "Found Home Manager configuration for $user_host"
                    set host $user_host
                    set config_type "homeConfigurations"
                    set rebuild_cmd "home-manager switch"
                else
                    # No exact match found, show available configurations
                    echo "Error: No configuration found for hostname '$host'"
                    echo ""
                    if test (count $nixos_configs) -gt 0
                        echo "Available NixOS configurations:"
                        for conf in $nixos_configs
                            echo "  - $conf"
                        end
                    end
                    if test (count $darwin_configs) -gt 0
                        echo "Available Darwin configurations:"
                        for conf in $darwin_configs
                            echo "  - $conf"
                        end
                    end
                    if test (count $home_configs) -gt 0
                        echo "Available Home Manager configurations:"
                        for conf in $home_configs
                            echo "  - $conf"
                        end
                    end
                    echo ""
                    echo "Usage: flake-rebuild [hostname]"
                    return 1
                end
            end

            # Pre-authenticate sudo if needed (for NixOS and Darwin)
            if test "$config_type" != "homeConfigurations"
                echo "Authenticating sudo..."
                sudo -v
                if test $status -ne 0
                    echo "sudo authentication failed"
                    return 1
                end

                # Setup system-level SOPS age key if needed (NixOS only)
                if test "$config_type" = "nixosConfigurations"
                    if not test -f /var/lib/sops-nix/key.txt
                        if test -f ~/.config/sops/age/keys.txt
                            echo "Setting up system-level SOPS age key..."
                            sudo mkdir -p /var/lib/sops-nix
                            sudo cp ~/.config/sops/age/keys.txt /var/lib/sops-nix/key.txt
                            sudo chmod 600 /var/lib/sops-nix/key.txt
                            sudo chown root:root /var/lib/sops-nix/key.txt
                            echo "System-level age key configured"
                        else
                            echo "Warning: No user age key found at ~/.config/sops/age/keys.txt"
                            echo "System secrets will not be available until age key is configured"
                        end
                    end
                end
            end

            # Run the appropriate rebuild command
            echo "Running $config_type rebuild for $host..."
            # Run in background to prevent shell lockup during rebuild
            eval $rebuild_cmd --flake "$flake_dir#$host" &

            # Wait for the background job to complete
            set rebuild_pid $last_pid
            wait $rebuild_pid
            set rebuild_status $status

            # Return the rebuild exit status
            return $rebuild_status
          '';
        };
      };
    };
  };
}
