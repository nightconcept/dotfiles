# AGENTS.md

Personal dotfiles as a Nix flake supporting NixOS, nix-darwin (macOS), and home-manager. All systems use `nixpkgs-unstable`.

**Windows** is its own island — managed by **yuki**, a personal declarative tool that wraps all Windows package manager frontends (Scoop, winget, etc.). See `windows/`.

Each major directory has a `CLAUDE.md` with context specific to that area — treat it as the AGENTS.md for that directory and read it when working there.

## Common Commands

```bash
# NixOS
nixos-rebuild switch --flake .#<hostname>        # tidus, aerith, barrett, rinoa, vincent

# Darwin
sudo darwin-rebuild switch --flake .#<hostname>  # waver, merlin

# Home Manager (standalone)
home-manager switch --flake '.#desktop'          # or laptop, server

# Flake
nix flake update   # update inputs
nix flake check    # validate
```

## Directory Map

| Path | Purpose |
|------|---------|
| `flake.nix` | Defines all system outputs |
| `lib/` | Helper functions (`mkNixos`, `mkNixosServer`, `mkDarwin`, `mkHome`) |
| `modules/nixos/` | NixOS system modules — see `modules/CLAUDE.md` |
| `modules/darwin/` | macOS system modules — see `modules/CLAUDE.md` |
| `modules/home/` | Home Manager modules — see `modules/CLAUDE.md` |
| `modules/nixos/security/` | SOPS secrets — see directory `CLAUDE.md` |
| `modules/nixos/services/docker/` | Docker containers — see directory `CLAUDE.md` |
| `modules/nixos/services/docker/containers/traefik/` | Traefik + CrowdSec — see directory `CLAUDE.md` |
| `home/` | Home Manager profiles and user config — see `home/CLAUDE.md` |
| `home/desktops/hyprland/` | Hyprland WM config — see directory `CLAUDE.md` |
| `hosts/` | Host-specific configs — see `hosts/CLAUDE.md` |
| `scripts/` | Bootstrap and utility scripts — see `scripts/CLAUDE.md` |
| `shared/` | Shared resources (e.g. `starship.toml`) |
| `iso/` | Custom NixOS installer ISO configs |
| `wallpaper/` | Wallpaper images |
| `windows/` | Windows config managed by yuki |
| `docs/` | Architecture and migration docs |

## Development Workflow

1. Edit relevant config files
2. Rebuild with the appropriate command above
3. Commit; run `nix flake update` periodically to refresh inputs
