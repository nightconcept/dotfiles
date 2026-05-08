# Architecture

## Directory Structure

- `/flake.nix` - Main flake configuration defining all system outputs
- `/lib/lib.nix` - Helper functions (`mkNixos`, `mkNixosServer`, `mkDarwin`, `mkHome`)
- `/modules/` - Reusable configuration modules organized by platform
  - `nixos/` - NixOS system modules
  - `darwin/` - macOS system modules
  - `home/` - Home Manager modules
  - `linux/` - Non-Nix Linux modules (pyinfra)
- `/home/` - Home Manager user configurations
- `/hosts/` - Host-specific configurations
  - `nixos/` - NixOS hosts
  - `darwin/` - macOS hosts
  - `linux/` - Non-Nix Linux hosts (Ubuntu, etc.)
- `/shared/` - Shared resources (e.g., starship.toml)
- `/iso/` - Custom installer ISO configurations
- `/scripts/` - Bootstrap and utility scripts
- `/windows/` - Windows-specific configurations (powershell, winutils)
- `/wallpaper/` - Wallpaper images for theming
- `/docs/` - Architecture and migration docs

## Configuration Hierarchy

### NixOS Systems
1. `flake.nix` calls `lib.mkNixos` or `lib.mkNixosServer`
2. Imports `./modules/nixos` (base NixOS modules)
3. Imports `./hosts/nixos/<hostname>` (host-specific config if exists)
4. Includes Home Manager with `./home` (uses `default.nix` selector)

### Darwin Systems
1. `flake.nix` calls `lib.mkDarwin`
2. Imports `./modules/darwin` (base Darwin modules)
3. Imports `./hosts/darwin/<hostname>` (host-specific config if exists)
4. Includes Home Manager with `./home` (uses `default.nix` selector)

### Home Manager Standalone
1. `flake.nix` calls `lib.mkHome`
2. Imports `./home` with hostname parameter
3. `default.nix` selects appropriate profiles based on hostname

### Linux Systems (Hybrid Management)
1. **System Layer**: Managed via **pyinfra** for declarative configuration of system-level tasks (e.g., packages, services, builds) on standard Linux distros (e.g., Ubuntu).
   - Deployed using `just <hostname>` (e.g., `just terra`).
2. **User Layer**: Managed via **Home Manager** for declarative user environment configuration (dotfiles, user tools).
   - Deployed using `home-manager switch --flake .#<hostname>` (e.g., `home-manager switch --flake .#terra`).
3. Uses `hosts/linux/<hostname>/main.py` for pyinfra entry point.
4. Leverages `modules/linux/` for system features and `home/profiles/` for user features.

## Profile System

The home configuration uses a profile-based system where `home/default.nix` selects the appropriate profiles based on hostname:

- **tidus**: `base + nixos-laptop` (Dell Latitude 7420 with Hyprland)
- **tidus-persist**: `base + nixos-laptop` (Impermanence variant)
- **aerith**: `base + server` (Plex media server)
- **barrett**: `base + server` (VPN torrent server)
- **rinoa**: `base + server` (Docker services)
- **vincent**: `base + server` (CI/CD runner with Docker)
- **waver**: `base + darwin-laptop` (MacBook Pro M1)
- **merlin**: `base + darwin-desktop` (Mac Mini M1)
- **desktop/laptop/server**: Generic standalone profiles

## Host Configurations

### Active NixOS Hosts
- `tidus` - Dell Latitude 7420 laptop with Hyprland desktop
- `tidus-persist` - Same as tidus but with impermanence for root filesystem
- `aerith` - Plex media server
- `barrett` - VPN torrent server with NordVPN
- `rinoa` - General purpose server (Docker services)
- `vincent` - CI/CD runner host with Docker and Forgejo runner

### Active Darwin Hosts
- `waver` - MacBook Pro M1
- `merlin` - Mac Mini M1 HTPC

### Active Linux Hosts (Non-Nix)
- `terra` - Ubuntu-based LLM inference server (managed via pyinfra)
  - Deploy with: `just terra`
