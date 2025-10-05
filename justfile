# Just commands for dotfiles-nix

# Check all flake configurations
check:
    NIXPKGS_ALLOW_UNFREE=1 nix flake check --impure

# Check home-manager configurations only
check-home:
    NIXPKGS_ALLOW_UNFREE=1 nix build .#homeConfigurations.desktop.activationPackage --dry-run --impure
    NIXPKGS_ALLOW_UNFREE=1 nix build .#homeConfigurations.laptop.activationPackage --dry-run --impure
    NIXPKGS_ALLOW_UNFREE=1 nix build .#homeConfigurations.server.activationPackage --dry-run --impure

# Check NixOS configurations only (may fail due to lix issues)
check-nixos:
    NIXPKGS_ALLOW_UNFREE=1 nix build .#nixosConfigurations.tidus.config.system.build.toplevel --dry-run --impure
    NIXPKGS_ALLOW_UNFREE=1 nix build .#nixosConfigurations.aerith.config.system.build.toplevel --dry-run --impure
    NIXPKGS_ALLOW_UNFREE=1 nix build .#nixosConfigurations.barrett.config.system.build.toplevel --dry-run --impure

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

# Format all Nix files
fmt:
    nix fmt
