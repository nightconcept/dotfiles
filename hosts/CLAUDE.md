# Host Configurations

Host-specific configs live in `hosts/nixos/<hostname>/` and `hosts/darwin/<hostname>/`. Hosts are wired into `flake.nix` via `lib.mkNixos`, `lib.mkNixosServer`, or `lib.mkDarwin`.

## NixOS Hosts

| Hostname | Description |
|----------|-------------|
| `tidus` | Dell Latitude 7420 laptop, Hyprland desktop |
| `aerith` | Plex media server |
| `barrett` | VPN torrent server (NordVPN) |
| `rinoa` | General purpose server (Docker services) |
| `vincent` | CI/CD runner (Docker + Forgejo runner) |

## Darwin Hosts

| Hostname | Description |
|----------|-------------|
| `waver` | MacBook Pro M1 |
| `merlin` | Mac Mini M1 HTPC |
