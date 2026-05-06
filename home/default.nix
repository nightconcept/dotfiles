# Main home-manager configuration selector
{
  config,
  lib,
  pkgs,
  hostname ? "",
  osConfig ? null,
  ...
}: let
  # Define profile mappings for each host
  profileMap = {
    # NixOS hosts
    tidus = {
      profiles = [./profiles/nixos-laptop.nix];
      username = "danny";
      homeDirectory = "/home/danny";
      extraImports = [];
      extraConfig = {
        targets.genericLinux.enable = true;
      };
    };

    aerith = {
      profiles = [./profiles/server.nix];
      username = "danny";
      homeDirectory = "/home/danny";
      extraImports = [];
      extraConfig = {};
    };

    barrett = {
      profiles = [./profiles/server.nix];
      username = "danny";
      homeDirectory = "/home/danny";
      extraImports = [];
      extraConfig = {};
    };

    rinoa = {
      profiles = [./profiles/server.nix];
      username = "danny";
      homeDirectory = "/home/danny";
      extraImports = [];
      extraConfig = {};
    };

    vincent = {
      profiles = [./profiles/server.nix];
      username = "danny";
      homeDirectory = "/home/danny";
      extraImports = [];
      extraConfig = {};
    };

    # Darwin hosts
    waver = {
      profiles = [./profiles/darwin-laptop.nix];
      username = "danny";
      homeDirectory = "/Users/danny";
      extraImports = [];
      extraConfig = {};
    };

    merlin = {
      profiles = [./profiles/darwin-desktop.nix];
      username = "danny";
      homeDirectory = "/Users/danny";
      extraImports = [];
      extraConfig = {};
    };

    # Generic standalone home-manager configurations
    desktop = {
      profiles = [./profiles/linux-desktop.nix];
      username = let envUser = builtins.getEnv "USER"; in if envUser != "" then envUser else "danny";
      homeDirectory = let envHome = builtins.getEnv "HOME"; in if envHome != "" then envHome else "/home/danny";
      extraImports = [];
      extraConfig = {
        targets.genericLinux.enable = true;
      };
    };

    laptop = {
      profiles = [./profiles/nixos-laptop.nix];
      username = let envUser = builtins.getEnv "USER"; in if envUser != "" then envUser else "danny";
      homeDirectory = let envHome = builtins.getEnv "HOME"; in if envHome != "" then envHome else "/home/danny";
      extraImports = [];
      extraConfig = {
        targets.genericLinux.enable = true;
      };
    };

    server = {
      profiles = [./profiles/server.nix];
      username = let envUser = builtins.getEnv "USER"; in if envUser != "" then envUser else "danny";
      homeDirectory = let envHome = builtins.getEnv "HOME"; in if envHome != "" then envHome else "/home/danny";
      extraImports = [];
      extraConfig = {};
    };

    # Default fallback
    default = {
      profiles = [./profiles/server.nix];
      username = let envUser = builtins.getEnv "USER"; in if envUser != "" then envUser else "danny";
      homeDirectory = let envHome = builtins.getEnv "HOME"; in if envHome != "" then envHome else "/home/danny";
      extraImports = [];
      extraConfig = {};
    };
  };

  # Get the configuration for the current host
  hostConfig = profileMap.${hostname} or profileMap.default;
in
  {
    imports =
      [./profiles/base.nix]
      ++ hostConfig.profiles
      ++ hostConfig.extraImports;

    home = {
      username = lib.mkForce hostConfig.username;
      homeDirectory = lib.mkForce hostConfig.homeDirectory;
    };
  }
  // hostConfig.extraConfig
