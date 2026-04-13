# AGENTS.md

Personal dotfiles as a Nix flake supporting NixOS, nix-darwin (macOS), and home-manager. All systems use `nixpkgs-unstable`.

**Windows** is its own island, managed by **yuki**, a personal declarative tool that wraps Windows package manager frontends. See `windows/`. Key packages include `opencode`, `vscode`, and `neovim`.

Each major directory has a `CLAUDE.md` with context specific to that area. Treat it as the `AGENTS.md` for that directory and read it when working there.

## Project Overview

This is a Nix flake configuration for personal dotfiles supporting multiple platforms:
- **NixOS**: Full system configurations for Linux desktops and servers
- **nix-darwin**: macOS system configurations
- **home-manager**: User-level configurations for any system

### Nixpkgs Strategy
- **All systems**: Use `nixpkgs-unstable` for latest features
- No overlays directory; packages are managed through module options

## Common Commands

### NixOS System Rebuild
```bash
# Switch to a NixOS configuration
nixos-rebuild switch --flake .#<CONFIG-NAME>

# Example configurations:
nixos-rebuild switch --flake .#tidus
nixos-rebuild switch --flake .#aerith
nixos-rebuild switch --flake .#barrett
```

### Darwin System Rebuild
```bash
# Switch to a Darwin configuration
sudo darwin-rebuild switch --flake .#<CONFIG-NAME>

# Example configurations:
sudo darwin-rebuild switch --flake .#waver
sudo darwin-rebuild switch --flake .#merlin
```

### Home Manager
```bash
# Standalone configurations
home-manager switch --flake '.#desktop'
home-manager switch --flake '.#laptop'
home-manager switch --flake '.#server'
```

### Flake Operations
```bash
# Update flake inputs
nix flake update

# Check flake configuration
nix flake check

# Show flake outputs
nix flake show
```

### Windows (yuki)
```powershell
# Install/update all yuki packages (Scoop, npm, etc.)
# Run from windows/ directory
yuki
```

## Architecture

### Directory Structure

- `/flake.nix` - Main flake configuration defining all system outputs
- `/lib/lib.nix` - Helper functions (`mkNixos`, `mkNixosServer`, `mkDarwin`, `mkHome`)
- `/modules/` - Reusable configuration modules organized by platform
  - `nixos/` - NixOS system modules
    - `core/` - Core system configuration (bootloader, locale, nix, packages, users)
    - `desktop/` - Desktop environment modules (hyprland, plasma6)
    - `hardware/` - Hardware configurations (bluetooth, graphics, power, printing, sound, usb-automount)
    - `kernel/` - Kernel configuration
    - `network/` - Network configuration
    - `networking/` - Network services and base configuration
    - `programs/` - System programs
    - `security/` - Security configuration (sops)
    - `services/` - System services (docker, nordvpn, openssh, plex, torrent)
    - `storage/` - Storage configuration (impermanence, network-drives)
  - `darwin/` - macOS system modules
    - `core/` - Core Darwin configuration
    - `homebrew/` - Homebrew package management
    - `system-settings/` - macOS system settings
  - `home/` - Home Manager modules
    - `programs/` - Program modules (nvim, shell, ghostty, wezterm)
    - `secrets/` - User-level sops secrets
    - `themes/` - Theme configuration
- `/home/` - Home Manager user configurations
  - `default.nix` - Profile selector based on hostname
  - `profiles/` - Composable configuration profiles
    - `base.nix` - Common to all systems
    - `linux-desktop.nix` - Generic Linux desktop
    - `nixos-laptop.nix` - NixOS laptop (Hyprland)
    - `darwin-laptop.nix` - macOS laptop
    - `darwin-desktop.nix` - macOS desktop
    - `server.nix` - Minimal server config
  - `programs/` - Application configurations
  - `desktops/` - Desktop environment configs (hyprland)
- `/hosts/` - Host-specific configurations
- `/shared/` - Shared resources (e.g., starship.toml)
- `/iso/` - Custom installer ISO configurations
- `/scripts/` - Bootstrap and utility scripts
- `/windows/` - Windows-specific configurations (powershell, winutils)
- `/wallpaper/` - Wallpaper images for theming
- `/docs/` - Architecture and migration docs

### Configuration Hierarchy

#### NixOS Systems
1. `flake.nix` calls `lib.mkNixos` or `lib.mkNixosServer`
2. Imports `./modules/nixos` (base NixOS modules)
3. Imports `./hosts/nixos/<hostname>` (host-specific config if exists)
4. Includes Home Manager with `./home` (uses `default.nix` selector)

#### Darwin Systems
1. `flake.nix` calls `lib.mkDarwin`
2. Imports `./modules/darwin` (base Darwin modules)
3. Imports `./hosts/darwin/<hostname>` (host-specific config if exists)
4. Includes Home Manager with `./home` (uses `default.nix` selector)

#### Home Manager Standalone
1. `flake.nix` calls `lib.mkHome`
2. Imports `./home` with hostname parameter
3. `default.nix` selects appropriate profiles based on hostname

### Profile System

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

### Key Components
- **Modules**: Self-contained feature modules in `/modules/{nixos,darwin,home}/`
- **Hosts**: Individual machine configs referenced in `flake.nix`
- **Programs**: User application configs in `/home/programs/`
- **Desktops**: Desktop environment configs in `/home/desktops/`
- **Themes**: Stylix theming in `modules/home/themes/`
- **Wallpapers**: Wallpaper images in `/wallpaper/`
- **Secrets**: SOPS-managed secrets in `modules/{nixos,home}/security/sops/`

### Module Options Pattern

Modules expose enable options and package options for flexibility:
```nix
options.modules.nixos.services.plex = {
  enable = mkEnableOption "Plex Media Server";
  package = mkOpt lib.types.package pkgs.plex "The plex package to use";
};
```

### Host Configurations

#### Active NixOS Hosts
- `tidus` - Dell Latitude 7420 laptop with Hyprland desktop
- `tidus-persist` - Same as tidus but with impermanence for root filesystem
- `aerith` - Plex media server
- `barrett` - VPN torrent server with NordVPN
- `rinoa` - General purpose server (Docker services)
- `vincent` - CI/CD runner host with Docker and Forgejo runner

#### Active Darwin Hosts
- `waver` - MacBook Pro M1
- `merlin` - Mac Mini M1 HTPC

### Docker Container Configuration

Docker services are managed as Nix modules in `/modules/nixos/services/docker/containers/`. Each container has its own module that defines:
- Docker compose configuration
- Environment variables
- Volume mounts
- Network configuration
- Traefik labels for reverse proxy

Available container modules include:
- **Media**: jellyfin, plex
- ***arr Stack**: sonarr, radarr, prowlarr, readarr, flaresolverr
- **Books**: audiobookshelf, calibre, calibre-web, readarr-books
- **Home Automation**: homepage, uptime-kuma
- **Infrastructure**: traefik, portainer, watchtower, cloudflare-tunnel
- **Authentication**: authelia, vaultwarden
- **Development**: forgejo, forgejo-runner
- **Gaming**: minecraft, enshrouded, palworld
- **Utilities**: freshrss, nextcloud, open-webui, searxng, wg-easy, ddclient, knot

Docker networks:
- `proxy` - Shared network for services behind Traefik reverse proxy

## Development Workflow

1. Make changes to relevant configuration files
2. Test changes locally with rebuild commands
3. Commit changes to git
4. The `flake.lock` should be updated periodically with `nix flake update`

## Hyprland Desktop Environment

The Hyprland configuration is modular and includes:

### Core Components (`/home/desktops/hyprland/`)
- `hyprland.nix` - Main Hyprland window manager configuration
- `waybar.nix` - Status bar configuration with Tokyo Night theme
- `hypridle.nix` - Idle management with power-aware timeouts
- `hyprlock.nix` - Lock screen with Mac-style interface
- `wlogout.nix` - Power menu with Stylix colors
- `wofi.nix` - Application launcher with Tokyo Night theme
- `mako.nix` - Notification daemon
- `gtk-settings.nix` - GTK theming

### Theming
- Uses Stylix with Tokyo Night color scheme
- Consistent theming across all applications
- Custom wallpaper support in `/wallpaper/`

### Key Bindings
- `Super+Return/T` - Open terminal (Ghostty)
- `Super+Space` - Application launcher (wofi)
- `Super+L` - Lock screen (hyprlock)
- `Super+Backspace` - Power menu (wlogout)
- `Alt+Tab` - Cycle windows
- `F1-F4` - Audio controls
- `F6-F7` - Brightness controls
- Print screen variations for screenshots

## Bootstrap Process

New systems can be bootstrapped using:
```bash
wget -qO- https://raw.githubusercontent.com/nightconcept/dotfiles-nix/main/bootstrap.sh | bash
```

The bootstrap script:
- Detects OS (NixOS, Linux, macOS)
- Installs Nix if needed
- Clones this repository
- On NixOS: Offers host selection (tidus/aerith)
- On Linux: Sets up Home Manager with profile selection
- On macOS: Provides manual instructions

## Terminal Emulator Installation

Terminal emulators (Ghostty, WezTerm) use `configOnly` mode on non-NixOS systems to avoid OpenGL/graphics library conflicts. This means:

- **Configuration**: Managed by Nix/home-manager
- **Binary installation**: Manual via native package managers

### Ghostty Installation

**NixOS:**
- Installed via nixpkgs: `modules.home.programs.ghostty.enable = true`

**Non-NixOS Linux:**
- Uses `configOnly` mode
- Manual installation required:
  - Arch: `yay -S ghostty`
  - Debian/Ubuntu: Download from https://github.com/mkasberg/ghostty-ubuntu/releases

**macOS:**
- Uses `configOnly` mode
- Installed via Homebrew (managed in `modules/darwin/homebrew/`)

### WezTerm Installation

Same pattern as Ghostty:
- **NixOS**: Via nixpkgs
- **Non-NixOS**: Manual installation via package manager
- **macOS**: Via Homebrew

### Why This Approach?

Using native package managers for GUI applications on non-NixOS systems:
- Avoids nixGL complexity and OpenGL library conflicts
- Works reliably with system graphics drivers
- Simpler to maintain and update
- Configuration still fully declarative via Nix

## SOPS Secret Management

Secrets are managed using sops-nix:
- System secrets configured in `/modules/nixos/security/sops/`
- User secrets configured in `/modules/home/secrets/`
- Age keys derived from SSH keys
- Automatic deployment to runtime directories

### Secret Storage Conventions

#### SOPS Encryption Key
**ALWAYS use `danny_personal` age key for all secrets**. Do not use host-specific keys as the personal key provides access across all systems.

#### Deployed Secret Paths
System services (NixOS) should use:
- `/run/secrets/<service>-<secret>` - Standard SOPS deployment path
- Example: `/run/secrets/nordvpn-token`

User services (home-manager) should use:
- `$XDG_RUNTIME_DIR/secrets/<secret>` - User runtime directory (tmpfs)
- Expands to `/run/user/1000/secrets/<secret>`
- Example: `/run/user/1000/secrets/brave_api_key`

#### Adding New Secrets
1. Edit the encrypted YAML file using `sops`
2. Add the secret definition in the appropriate module's sops configuration
3. Follow the path conventions above for consistency
