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
| `check-repo-deps.py` | Report repos behind `shared/dev-builds.toml` (`just check-repo-deps [paths]`, default `~/git`) |
| `bench-qwen38-spec.py` | Benchmark Qwen3.8 server speculation and restore Hermes |
| `setup-keys.sh` | SSH key setup |
| `locke-pool-alert.sh` | Gotify alert when Locke's thin pool passes 90 % (hand-installed on Locke; see `docs/network.md`) |
| `install-terminal.sh` | Install terminal emulator (Ghostty/WezTerm) |
| `switch-to-upstream-nix.sh` | Switch from distro Nix to upstream |
| `watchtower` | One-shot update for all Docker containers on local or remote host |
