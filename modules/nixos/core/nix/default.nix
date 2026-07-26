# Nix configuration module
{
  config,
  lib,
  inputs,
  ...
}:
with lib; let
  cfg = config.modules.nixos.core.nix;
in {
  options.modules.nixos.core.nix = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Nix configuration";
    };
  };

  config = mkIf cfg.enable {
    nix = {
      settings = {
        auto-optimise-store = true;
        trusted-users = ["root" "@wheel" "danny"];
        experimental-features = ["nix-command" "flakes"];
        use-xdg-base-directories = true;
        warn-dirty = false;
        keep-outputs = true;
        keep-derivations = true;

        # Build performance optimizations
        max-jobs = "auto";
        cores = 0; # Use all available cores

        # Additional binary caches for faster builds
        substituters = [
          "https://cache.nixos.org/"
          "https://nix-community.cachix.org"
          "https://cuda-maintainers.cachix.org"
        ];
        trusted-public-keys = [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
          "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
        ];

        # Allow building during downloads
        builders-use-substitutes = true;

        # Speed up builds
        connect-timeout = 5;
        log-lines = 25;

        # Enable parallel downloading
        http-connections = 25;
        max-substitution-jobs = 50;
        download-buffer-size = 524288000; # 500 MiB (default 64 MiB)

        # Additional performance optimizations
        build-poll-interval = 0;
        narinfo-cache-negative-ttl = 0;
        tarball-ttl = 0;
      };
      gc = {
        automatic = true;
        dates = "weekly";
        options = "--delete-older-than 30d";
      };
    };

    nixpkgs = {
      hostPlatform = lib.mkDefault "x86_64-linux";
      config.allowUnfree = true;
      overlays = lib.optionals (inputs ? nixpkgs-master) [
        (final: prev: {
          claude-code = (import inputs.nixpkgs-master {
            system = prev.stdenv.hostPlatform.system;
            config.allowUnfree = true;
          }).claude-code;
        })
      ];
    };
  };
}
