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
      homeDirectory = "/home/danny";
      extraImports = [];
      extraConfig = {
        targets.genericLinux.enable = true;
      };
    };

    aerith = {
      profiles = [./profiles/server.nix];
      homeDirectory = "/home/danny";
      extraImports = [];
      extraConfig = {};
    };

    barrett = {
      profiles = [./profiles/server.nix];
      homeDirectory = "/home/danny";
      extraImports = [];
      extraConfig = {};
    };

    rinoa = {
      profiles = [./profiles/server.nix];
      homeDirectory = "/home/danny";
      extraImports = [];
      extraConfig = {};
    };

    vincent = {
      profiles = [./profiles/server.nix];
      homeDirectory = "/home/danny";
      extraImports = [];
      extraConfig = {};
    };

    # Darwin hosts
    waver = {
      profiles = [./profiles/darwin-laptop.nix];
      homeDirectory = "/Users/danny";
      extraImports = [];
      extraConfig = {};
    };

    merlin = {
      profiles = [./profiles/darwin-desktop.nix];
      homeDirectory = "/Users/danny";
      extraImports = [];
      extraConfig = {};
    };

    # Generic standalone home-manager configurations
    desktop = {
      profiles = [./profiles/linux-desktop.nix];
      homeDirectory = builtins.getEnv "HOME";
      extraImports = [];
      extraConfig = {
        targets.genericLinux.enable = true;
      };
    };

    laptop = {
      profiles = [./profiles/nixos-laptop.nix];
      homeDirectory = builtins.getEnv "HOME";
      extraImports = [];
      extraConfig = {
        targets.genericLinux.enable = true;
      };
    };

    server = {
      profiles = [./profiles/server.nix];
      homeDirectory = builtins.getEnv "HOME";
      extraImports = [];
      extraConfig = {};
    };

    # Default fallback
    default = {
      profiles = [./profiles/server.nix];
      homeDirectory = builtins.getEnv "HOME";
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
  }
  // (lib.optionalAttrs (hostConfig.homeDirectory != "") {
    home.homeDirectory = lib.mkForce hostConfig.homeDirectory;
  })
  // hostConfig.extraConfig
