# dotfiles

NixOS, macOS, and Linux system configurations managed by [Nix](https://nixos.org/) and (soon) Windows system configurations managed by Ame (WIP).

## Uses

- **Shell**: fish
- **Terminal**: wezterm
- **Editor**: neovim/vscode
- **Desktop**: Hyprland (NixOS)
- **Theme**: Tokyo Night
- **Font**: Inter Nerd Font/Fira Code Nerd Font


## Configuration Paths
- NixOS Laptop - Hyprland DE
- NixOS Server - Headless Plex Server
- Darwin Laptop - Aerospace DE with common macOS applications
- Darwin Desktop - Regular macOS with common macOS applications
- Linux Desktop - Desktop + CLI Linux Applications
- Linux Server - CLI Linux Applications

## Hosts

### NixOS & Darwin Hosts

| Host | Type | Hardware | Purpose |
|------|------|----------|---------|
| `tidus` | NixOS | Dell Latitude 7420 | Linux Laptop with Hyprland DE |
| `aerith` | NixOS | VM | Plex media server |
| `rinoa` | NixOS | VM | General purpose server |
| `vincent` | NixOS | VM | CI/CD runner host |
| `waver` | Darwin | MacBook Pro M1 | macOS Laptop with Aerospace DE |
| `merlin` | Darwin | Mac Mini M1 | macOS Desktop HTPC |

### Imperative Setups (Non-Nix)

| Host | Type | Hardware | Purpose |
|------|------|----------|---------|
| `barrett` | Debian | VM | VPN torrent server |

## Homes

| Home | Type | Hardware | Purpose |
|------|------|----------|---------|
| `desktop` | Linux | Any | Linux Computer with common desktop and CLI tools |
| `server` | Linux | Any | Linux Server with common CLI tools |

## Quick Start

```bash
wget -qO- https://forge.solivan.dev/nightconcept/dotfiles/raw/branch/main/bootstrap.sh | bash
```

For fresh NixOS server installations, see the [Server Setup Runbook](docs/server-setup-runbook.md) which covers pre-bootstrap steps like enabling SSH and setting up networking.

## Manual Usage

### NixOS
```bash
nixos-rebuild switch --flake .#tidus
nixos-rebuild switch --flake .#aerith
nixos-rebuild switch --flake .#rinoa
nixos-rebuild switch --flake .#vincent
```

### Darwin
```bash
sudo darwin-rebuild switch --flake .#waver
sudo darwin-rebuild switch --flake .#merlin
```

### Home Manager (standalone)
```bash
nix run home-manager/master -- switch --flake .#desktop
nix run home-manager/master -- switch --flake .#server
```

### Barrett (Debian - Imperative Setup)
```bash
# Run the setup script (will print further instructions)
sudo bash ./scripts/barrett-setup.sh
```

## License

[MIT](LICENSE)
