# Modules

Reusable configuration modules organized by platform. Each module is self-contained and exposes enable/package options.

## Module Options Pattern

```nix
options.modules.nixos.services.plex = {
  enable = mkEnableOption "Plex Media Server";
  package = mkOpt lib.types.package pkgs.plex "The plex package to use";
};
```

## Platform Directories

- `nixos/` — NixOS system modules (core, desktop, hardware, kernel, networking, programs, security, services, storage)
- `darwin/` — macOS modules (core, homebrew, system-settings)
- `home/` — Home Manager modules (programs, secrets, themes)

## Configuration Hierarchy

### NixOS
`flake.nix` → `lib.mkNixos` → imports `./modules/nixos` → host config → home-manager via `./home`

### Darwin
`flake.nix` → `lib.mkDarwin` → imports `./modules/darwin` → host config → home-manager via `./home`

### Home Manager standalone
`flake.nix` → `lib.mkHome` → imports `./home` with hostname
