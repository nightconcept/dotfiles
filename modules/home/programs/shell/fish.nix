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
        "${config.home.homeDirectory}/.local/bin"
        "/opt/nvim-linux64/bin"
      ]
      ++ (
        if pkgs.stdenv.isDarwin
        then [
          "/usr/local/bin"
          "/opt/homebrew/bin"
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
        set -gx XDG_DATA_DIRS ${config.home.homeDirectory}/.nix-profile/share $XDG_DATA_DIRS

        # Ensure Nix is in PATH
        if test -d "/nix/var/nix/profiles/default/bin"
            fish_add_path --prepend /nix/var/nix/profiles/default/bin
        end
        ${
          if pkgs.stdenv.isDarwin
          then ''
            if test -d "${config.home.homeDirectory}/.nix-profile/bin"
                fish_add_path --prepend ${config.home.homeDirectory}/.nix-profile/bin
            end
            if test -d "/etc/profiles/per-user/${config.home.username}/bin"
                fish_add_path --prepend /etc/profiles/per-user/${config.home.username}/bin
            end
            if test -d "/run/current-system/sw/bin"
                fish_add_path --prepend /run/current-system/sw/bin
            end
          ''
          else ''
            if test -d "${config.home.homeDirectory}/.nix-profile/home-path/bin"
                fish_add_path --prepend ${config.home.homeDirectory}/.nix-profile/home-path/bin
            end
            if test -d "${config.home.homeDirectory}/.nix-profile/bin"
                fish_add_path --prepend ${config.home.homeDirectory}/.nix-profile/bin
            end
          ''
        }

        # Conditional brew setup
        if test -d "/home/linuxbrew/"
            eval (/home/linuxbrew/.linuxbrew/bin/brew shellenv)
        end

        # ROCm setup (Ubuntu/Manual installs)
        if test -d "/opt/rocm"
            fish_add_path --prepend /opt/rocm/bin
            if set -q LD_LIBRARY_PATH
                set -gx LD_LIBRARY_PATH "/opt/rocm/lib:$LD_LIBRARY_PATH"
            else
                set -gx LD_LIBRARY_PATH "/opt/rocm/lib"
            end
            set -gx ROCM_PATH "/opt/rocm"
            set -gx HIP_CLANG_PATH "/opt/rocm/llvm/bin"
        end

        # UV tool path setup
        if test -d "${config.home.homeDirectory}/.local/share/uv/tools"
            for tool_dir in ${config.home.homeDirectory}/.local/share/uv/tools/*/bin
                if test -d "$tool_dir"
                    fish_add_path --prepend "$tool_dir"
                end
            end
        end

        # NPM global bin path for claude-sandbox
        if test -d "${config.home.homeDirectory}/.npm-global/bin"
            fish_add_path --prepend ${config.home.homeDirectory}/.npm-global/bin
        end

        # Enable OpenCode built-in Exa web search (no API key required)
        set -gx OPENCODE_ENABLE_EXA true

        if command -q mise
            mise activate fish | source
        end
      '';

      plugins = [
        # {
        #   name = "done";
        #   src = pkgs.fishPlugins.done.src;
        # }
        {
          name = "fzf-fish";
          src = pkgs.fishPlugins.fzf-fish.src;
        }
        {
          name = "autopair";
          src = pkgs.fishPlugins.autopair.src;
        }
        # {
        #   name = "sponge";
        #   src = pkgs.fishPlugins.sponge.src;
        # }
      ];

      functions = {
        fish_greeting = {
          description = "Greeting to show when starting a fish shell";
          body = "";
        };

        garbage-collect = {
          description = "Free disk space: clean Nix garbage, repo build artifacts, caches, and /tmp";
          body = ''
            # Snapshot available space across /nix, $HOME, and /tmp filesystems (deduped by device)
            set before (df -Pk $HOME /nix /tmp 2>/dev/null | tail -n +2 | sort -u -k1,1 | awk '{sum+=$4} END{print sum+0}')

            # Nix garbage collection (remove old generations + collect garbage)
            nix-collect-garbage -d

            # Clean Rust and other build artifacts in known repo roots.
            for repo_root in $HOME/git $HOME/Documents/GitHub
                if test -d "$repo_root"
                    ${pkgs.kondo}/bin/kondo --all -qq "$repo_root" 2>/dev/null
                end
            end

            # Clear user cache directories that are safe to recreate.
            for cache_dir in \
                "$HOME/Library/Caches" \
                "$HOME/.cache" \
                "$HOME/.npm" \
                "$HOME/Library/pnpm/store" \
                "$HOME/Library/Application Support/Code/CachedExtensionVSIXs" \
                "$HOME/Library/Developer/CoreSimulator/Caches" \
                "$HOME/Library/Application Support/discord/Cache" \
                "$HOME/Library/Application Support/discord/Code Cache" \
                "$HOME/Library/Application Support/discord/GPUCache" \
                "$HOME/Library/Application Support/discord/Service Worker/CacheStorage" \
                "$HOME/Library/Application Support/Slack/Cache" \
                "$HOME/Library/Application Support/Slack/Service Worker/CacheStorage"
                if test -d "$cache_dir"
                    find "$cache_dir" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null
                end
            end

            # Prune unavailable simulator devices after clearing simulator caches.
            if command -q xcrun
                xcrun simctl delete unavailable >/dev/null 2>&1
            end

            # Clean stale user-owned /tmp files: Claude session dirs, cargo artifacts, core dumps, files >1 day old
            find /tmp -maxdepth 1 -user $USER \( -name "claude-*" -o -name "cargo-*" -o -name "core" -o -name "*.core" \) -exec rm -rf {} + 2>/dev/null
            find /tmp -maxdepth 1 -user $USER -mtime +1 -exec rm -rf {} + 2>/dev/null

            # Snapshot available space after cleanup
            set after (df -Pk $HOME /nix /tmp 2>/dev/null | tail -n +2 | sort -u -k1,1 | awk '{sum+=$4} END{print sum+0}')

            # Calculate freed space in KB (available space increased)
            set freed_kb (math $after - $before)

            if test $freed_kb -le 0
                echo "No disk space freed"
                return 0
            end

            if test $freed_kb -ge 1048576
                set amount (math --scale=1 $freed_kb / 1048576)
                echo "Freed "$amount" GB"
            else if test $freed_kb -ge 1024
                set amount (math --scale=1 $freed_kb / 1024)
                echo "Freed "$amount" MB"
            else
                echo "Freed "$freed_kb" KB"
            end
          '';
        };

        flake-rebuild = {
          description = "Smart flake rebuild that auto-detects system and hostname, deploys remotely if host differs from local";
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

            # Determine if this is a remote deploy
            set local_host (hostname -s)
            set remote false
            if test "$host" != "$local_host"
                set remote true
                echo "Remote deploy: $local_host → $host"
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

            # Check for pyinfra host first (not tracked in the flake)
            if test -f "$flake_dir/hosts/linux/$host/main.py"
                echo "Found pyinfra configuration for $host"
                if test "$remote" = true
                    echo "Running remote pyinfra deploy..."
                    uv run --with pyinfra --with requests pyinfra -y (whoami)@$host "$flake_dir/hosts/linux/$host/main.py" &
                else
                    echo "Running local pyinfra deploy..."
                    uv run --with pyinfra --with requests pyinfra -y @local "$flake_dir/hosts/linux/$host/main.py" &
                end
                set pyinfra_pid $last_pid
                wait $pyinfra_pid
                return $status
            end

            # Check what configurations are available in the flake for this hostname
            set nixos_configs (nix eval --impure $flake_dir#nixosConfigurations --apply 'x: builtins.attrNames x' 2>/dev/null | tr -d '[]"' | tr ' ' '\n')
            set darwin_configs (nix eval --impure $flake_dir#darwinConfigurations --apply 'x: builtins.attrNames x' 2>/dev/null | tr -d '[]"' | tr ' ' '\n')
            set home_configs (nix eval --impure $flake_dir#homeConfigurations --apply 'x: builtins.attrNames x' 2>/dev/null | tr -d '[]"' | tr ' ' '\n')

            # Check if hostname exists in any configuration type
            if contains $host $nixos_configs
                echo "Found NixOS configuration for $host"
                set config_type "nixosConfigurations"
                if test "$remote" = true
                    # Build and activate on the remote host itself; avoids cross-compilation from Mac
                    set rebuild_cmd "nixos-rebuild switch --target-host (whoami)@$host --build-host (whoami)@$host --use-remote-sudo"
                else
                    set rebuild_cmd "sudo nixos-rebuild switch"
                end
            else if contains $host $darwin_configs
                echo "Found Darwin configuration for $host"
                set config_type "darwinConfigurations"
                if test "$remote" = true
                    echo "Error: Remote Darwin deploys are not supported"
                    return 1
                end
                set rebuild_cmd "sudo darwin-rebuild switch"
            else if contains $host $home_configs
                echo "Found Home Manager configuration for $host"
                set config_type "homeConfigurations"
                set rebuild_cmd "home-manager switch --impure"
            else
                # Try user@host format for home-manager
                set user_host (whoami)@$host
                if contains $user_host $home_configs
                    echo "Found Home Manager configuration for $user_host"
                    set host $user_host
                    set config_type "homeConfigurations"
                    set rebuild_cmd "home-manager switch --impure"
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

            # For local NixOS/Darwin deploys: pre-authenticate sudo and ensure SOPS key
            if test "$remote" = false -a "$config_type" != "homeConfigurations"
                echo "Authenticating sudo..."
                sudo -v
                if test $status -ne 0
                    echo "sudo authentication failed"
                    return 1
                end

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
            if test "$config_type" = "homeConfigurations"
                eval $rebuild_cmd --flake "$flake_dir#$host" --impure &
            else
                eval $rebuild_cmd --flake "$flake_dir#$host" &
            end

            # Wait for the background job to complete
            set rebuild_pid $last_pid
            wait $rebuild_pid
            set rebuild_status $status

            # Return the rebuild exit status
            return $rebuild_status
          '';
        };

        flake-boot = {
          description = "Boot a NixOS flake configuration that will be activated after reboot";
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

            # Check what NixOS configurations are available in the flake for this hostname
            set nixos_configs (nix eval --impure $flake_dir#nixosConfigurations --apply 'x: builtins.attrNames x' 2>/dev/null | tr -d '[]"' | tr ' ' '\n')

            if not contains $host $nixos_configs
                echo "Error: No NixOS configuration found for hostname '$host'"
                echo ""
                if test (count $nixos_configs) -gt 0
                    echo "Available NixOS configurations:"
                    for conf in $nixos_configs
                        echo "  - $conf"
                    end
                end
                echo ""
                echo "Usage: flake-boot [hostname]"
                return 1
            end

            echo "Found NixOS configuration for $host"
            echo "Authenticating sudo..."
            sudo -v
            if test $status -ne 0
                echo "sudo authentication failed"
                return 1
            end

            # Setup system-level SOPS age key if needed
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

            echo "Running nixosConfigurations boot for $host..."
            eval sudo nixos-rebuild boot --flake "$flake_dir#$host" &

            set rebuild_pid $last_pid
            wait $rebuild_pid
            set rebuild_status $status

            return $rebuild_status
          '';
        };
      };
    };
  };
}
