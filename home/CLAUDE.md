# Home Manager Configuration

## Profile System

`home/default.nix` selects profiles based on hostname:

| Hostname | Profiles |
|----------|---------|
| `tidus` | `base + nixos-laptop` (Dell Latitude 7420, Hyprland) |
| `aerith` | `base + server` (Plex media server) |
| `barrett` | `base + server` (VPN torrent server) |
| `rinoa` | `base + server` (Docker services) |
| `vincent` | `base + server` (CI/CD runner) |
| `waver` | `base + darwin-laptop` (MacBook Pro M1) |
| `merlin` | `base + darwin-desktop` (Mac Mini M1) |
| `desktop` / `laptop` / `server` | Generic standalone profiles |

## Directory Structure

- `default.nix` — Profile selector (entry point)
- `profiles/` — Composable profiles (`base`, `nixos-laptop`, `darwin-laptop`, `darwin-desktop`, `server`, `linux-desktop`)
- `programs/` — Application configurations
- `desktops/` — Desktop environment configs (`hyprland/`, `niri/`, `aerospace/`)

## Configuration Hierarchy

NixOS/Darwin systems include home-manager via `./home` (default.nix selects profile by hostname).
Standalone: `flake.nix` calls `lib.mkHome` with a hostname parameter.
