# Steam gaming platform with Proton-GE support
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.modules.nixos.programs.steam;
in {
  options.modules.nixos.programs.steam = {
    enable = mkEnableOption "Steam gaming platform";
  };

  config = mkIf cfg.enable {
    # Enable Steam with all recommended settings
    programs.steam = {
      enable = true;

      # Enable Steam Remote Play
      remotePlay.openFirewall = true;

      # Enable Steam Local Network Game Transfers
      dedicatedServer.openFirewall = true;

      # Enable Steam local multiplayer
      localNetworkGameTransfers.openFirewall = true;

      # Enable gamescope compositor session (SteamOS-like experience)
      gamescopeSession.enable = true;

      # Additional packages to install in Steam's FHS environment
      extraCompatPackages = with pkgs; [
        proton-ge-bin # Proton-GE for better game compatibility
      ];

      # Package overrides for Steam
      package = pkgs.steam.override {
        extraPkgs = pkgs:
          with pkgs; [
            # Core libraries
            libxcursor
            libxi
            libxinerama
            libxscrnsaver
            libpng
            libpulseaudio
            libvorbis
            stdenv.cc.cc.lib
            libkrb5
            keyutils

            # GameMode for performance optimization
            gamemode

            # MangoHud for performance monitoring overlay
            mangohud

            # Additional graphics libraries
            mesa
            vulkan-loader
            vulkan-validation-layers
            vulkan-tools

            # Font libraries for games
            liberation_ttf
            source-han-sans
            source-han-serif
          ];
      };
    };

    # Install gaming utilities system-wide
    environment.systemPackages = with pkgs; [
      # Proton-GE updater/manager
      protonup-qt

      # Performance tools
      gamemode
      gamescope # SteamOS compositor for improved gaming performance
      mangohud # Performance overlay

      # Protontricks for running Windows executables
      protontricks

      # Steam utilities
      steamcmd # Steam console client
      steam-tui # Terminal UI for Steam
    ];

    # GameMode configuration
    programs.gamemode = {
      enable = true;
      settings = {
        general = {
          # Automatically renice games for better performance
          renice = 10;
        };
        # GPU optimizations
        gpu = {
          # Apply GPU performance mode
          apply_gpu_optimisations = "accept-responsibility";
          gpu_device = 0;
          amd_performance_level = "high";
        };
        # Custom scripts can be added here if needed
        custom = {
          start = "${pkgs.libnotify}/bin/notify-send 'GameMode started'";
          end = "${pkgs.libnotify}/bin/notify-send 'GameMode ended'";
        };
      };
    };

    # Ensure 32-bit graphics support is enabled (required for most games)
    # This is already handled by the graphics module, but we verify it here
    assertions = [
      {
        assertion = config.hardware.graphics.enable32Bit or false;
        message = "Steam requires 32-bit graphics support. Enable modules.nixos.hardware.graphics with enable32Bit.";
      }
    ];
  };
}
