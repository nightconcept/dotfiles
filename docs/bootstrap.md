# Bootstrap Process

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
