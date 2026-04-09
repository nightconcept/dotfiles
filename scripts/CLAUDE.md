# Scripts

## Bootstrap

New systems bootstrap via:
```bash
wget -qO- https://raw.githubusercontent.com/nightconcept/dotfiles-nix/main/bootstrap.sh | bash
```

The script:
- Detects OS (NixOS, Linux, macOS)
- Installs Nix if needed
- Clones this repository
- NixOS: offers host selection (tidus/aerith)
- Linux: sets up Home Manager with profile selection
- macOS: provides manual instructions

## Other Scripts

| Script | Purpose |
|--------|---------|
| `add-host-to-sops.sh` | Register a new host's key with SOPS |
| `barrett-setup.sh` | Initial barrett server setup |
| `setup-keys.sh` | SSH key setup |
| `install-terminal-debian.sh` | Install terminal emulator on Debian/Ubuntu |
| `build-tidus-persist-iso.sh` | Build custom NixOS installer ISO |
| `switch-to-upstream-nix.sh` | Switch from distro Nix to upstream |
