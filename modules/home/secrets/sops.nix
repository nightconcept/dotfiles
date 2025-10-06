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
        # Gemini API key - deployed to a file that shell can source
        "gemini_api_key" = {
          # Use XDG runtime dir for better security (tmpfs, user-only access)
          path = "%r/secrets/gemini_api_key";
          mode = "0400";
        };

        # Forgejo git personal access token
        "forgejo_git_token" = {
          # Use home directory path on macOS since XDG_RUNTIME_DIR isn't standard
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

        # Other user secrets can be added here
      };
    };

    # Ensure the age keys directory exists
    home.file.".config/sops/age/.keep".text = "";
  };
}
