# Just commands for dotfiles-nix

default:
    @just --list

# Check all flake configurations
check:
    NIXPKGS_ALLOW_UNFREE=1 nix flake check --impure

# Check home-manager configurations only
check-home:
    NIXPKGS_ALLOW_UNFREE=1 nix build .#homeConfigurations.desktop.activationPackage --dry-run --impure
    NIXPKGS_ALLOW_UNFREE=1 nix build .#homeConfigurations.laptop.activationPackage --dry-run --impure
    NIXPKGS_ALLOW_UNFREE=1 nix build .#homeConfigurations.server.activationPackage --dry-run --impure

# Check NixOS configurations only (barrett excluded — now Debian/pyinfra)
check-nixos:
    NIXPKGS_ALLOW_UNFREE=1 nix build .#nixosConfigurations.tidus.config.system.build.toplevel --dry-run --impure
    NIXPKGS_ALLOW_UNFREE=1 nix build .#nixosConfigurations.aerith.config.system.build.toplevel --dry-run --impure

# Check Darwin configurations only (may fail due to stylix issues)
check-darwin:
    NIXPKGS_ALLOW_UNFREE=1 nix build .#darwinConfigurations.waver.system --dry-run --impure
    NIXPKGS_ALLOW_UNFREE=1 nix build .#darwinConfigurations.merlin.system --dry-run --impure

# Update flake inputs
update:
    nix flake update

# Show flake outputs
show:
    nix flake show

# Build a specific NixOS configuration without switching
build-nixos config:
    nixos-rebuild build --flake .#{{config}}

# Build a specific Darwin configuration without switching
build-darwin config:
    darwin-rebuild build --flake .#{{config}}

# Build a specific Home Manager configuration without switching
build-home config:
    home-manager build --flake .#{{config}}

# Switch to a NixOS configuration
switch-nixos config:
    sudo nixos-rebuild switch --flake .#{{config}}

# Switch to a Darwin configuration
switch-darwin config:
    sudo darwin-rebuild switch --flake .#{{config}}

# Switch to a Home Manager configuration
switch-home config:
    home-manager switch --flake .#{{config}}

# Clean up build artifacts
clean:
    sudo nix-collect-garbage -d

# Deploy Terra host (Ubuntu) using pyinfra
terra:
    uv run --with pyinfra --with requests pyinfra -y @local hosts/linux/terra/main.py

# Run the LibbyRip converter locally without Traefik
dev:
    mkdir -p .local/state/libbyrip-converter-dev
    LIBBYRIP_REPO="${PWD}/../LibbyRip" LIBBYRIP_DATA_DIR="${PWD}/.local/state/libbyrip-converter-dev" docker compose -f modules/linux/programs/libbyrip_converter/docker-compose.dev.yml up -d --build

# Stop the local LibbyRip converter dev container
dev-down:
    LIBBYRIP_REPO="${PWD}/../LibbyRip" LIBBYRIP_DATA_DIR="${PWD}/.local/state/libbyrip-converter-dev" docker compose -f modules/linux/programs/libbyrip_converter/docker-compose.dev.yml down

# Start the Palworld dedicated server (1.0-ready; not deployed on this machine yet)
palworld:
    cd modules/nixos/services/docker/containers/palworld && docker compose up -d

# Deploy Barrett host (Debian VPN torrent server) using pyinfra
barrett:
    uv run --with pyinfra --with requests pyinfra -y @local hosts/linux/barrett/main.py

# Validate Barrett modules without sudo (syntax, rendered configs, correctness checks)
barrett-check:
    python3 scripts/barrett-validate.py

# Run the default local llama.cpp chat model
llama:
    llama-cli -m /opt/llm-models/Qwen3.6-35B-A3B-UD-Q6_K.gguf -c 131072 -ngl all -fa on -ctk f16 -ctv f16 --no-mmproj --jinja -cnv

# Format all Nix files
fmt:
    find . -name "*.nix" -type f | xargs nix fmt

# Format and lint Python files
py-fmt:
    uv run ruff format .
    uv run ruff check --fix .

# Type check Python files
py-check:
    uv run ty check .

# Edit SOPS secrets
edit-sops:
    SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt sops modules/nixos/security/sops/common.yaml

# Test starship configuration without rebuilding
test-starship:
    rm -f ~/.config/starship.toml
    cp shared/starship.toml ~/.config/starship.toml
    @echo "✓ Starship config copied!"
    @echo "Press Enter in your terminal to reload (starship reloads automatically on each prompt)"
    @echo "Or run: exec fish"
