{
  config,
  lib,
  ...
}: let
  # Import our custom lib functions
  moduleLib = import ../../../lib/module {inherit lib;};
  inherit (moduleLib) mkBoolOpt enabled disabled;
in {
  options.modules.home.programs.git = {
    enable = mkBoolOpt true "Enable git with comprehensive configuration";
  };

  config = lib.mkIf config.modules.home.programs.git.enable {
    # Note: Forgejo authentication is handled by the credential helper below
    # No activation script needed since we use credential helper instead of URL rewrite

    programs.git = {
      enable = true;

      signing = {
        key = "~/.ssh/id_sdev.pub";
        signByDefault = true;
      };

      settings = {
        user = {
          name = "Danny Solivan";
          email = "dark@nightconcept.net";
        };
        gpg = {
          format = "ssh";
          ssh.allowedSignersFile = "~/.ssh/allowed_signers";
        };

        tag = {
          gpgSign = true; # Also sign tags
        };

        commit = {
          gpgSign = true; # Ensure commits are signed
        };

        github = {
          user = "nightconcept";
        };

        # Forgejo configuration
        "url \"https://forge.solivan.dev\"" = {
          insteadOf = [
            "forgejo:"
          ];
        };

        alias = {
          del = "branch -D";
          undo = "reset HEAD~ --mixed";
          clear = "!git reset --hard";
        };
        core = {
          excludesfile = "~/.gitnignore";
          editor = "code";
          pager = "delta";
          ignorecase = false;
          rebase = false;
        };

        color = {
          status = "auto";
          diff = "auto";
          branch = "auto";
          interactive = "auto";
          grep = "auto";
          ui = true;
        };

        interactive = {
          diffFitler = "delta --color-only";
        };

        delta = {
          enable = true;
          navigate = true;
          light = false;
          side-by-side = false;
          options.syntax-theme = "catppuccin";
        };

        fetch = {
          prune = false;
        };

        pull = {
          ff = "only";
        };

        push = {
          default = "current";
        };

        rebase = {
          autoStash = true;
          autosquash = true;
        };

        init = {
          defaultBranch = "main";
        };

        hub = {
          protocol = "https";
        };

        # Automatically rewrite HTTPS URLs to SSH for GitHub
        "url \"git@github.com:\"" = {
          insteadOf = [
            "https://github.com/"
            "https://www.github.com/"
          ];
        };

        # Configure credentials for Forgejo
        "credential \"https://forge.solivan.dev\"" = {
          helper = "!f() { echo \"username=nightconcept\"; echo \"password=$(cat ~/.local/share/sops/secrets/forgejo_git_token 2>/dev/null || echo 'token-not-found')\"; }; f";
        };

        "filter \"lfs\"" = {
          process = "git-lfs filter-process";
          required = true;
          clean = "git-lfs clean -- %f";
          smudge = "git-lfs smudge -- %f";
        };
      };
    };

    # Create the allowed signers file for SSH signing verification
    home.file.".ssh/allowed_signers".text = ''
      dark@nightconcept.net ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMJKTm63zFmYfGauCBlUWq7lvHFq+NVPT5RqIfjLM7MN danny@solivan.dev
    '';
  };
}
