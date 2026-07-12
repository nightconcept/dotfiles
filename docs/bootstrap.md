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

## Non-NixOS Linux Hosts (terra, barrett)

These hosts are bootstrapped automatically by their pyinfra deploy. Run from any machine that has the dotfiles checked out:

```bash
flake-rebuild terra    # or: just terra
flake-rebuild barrett  # or: just barrett
```

`flake-rebuild` compares your local hostname to the target and runs pyinfra locally (`@local`) or remotely over SSH (`user@host`) as appropriate. The pyinfra `HomeManagerModule` handles the full bootstrap sequence on the target host:

1. Installs `git`, `curl`, `xz-utils` via apt
2. Installs Nix via the Determinate Systems installer (skipped if already present)
3. Clones the dotfiles to `~/git/dotfiles` (skipped if already present)
4. Installs `home-manager` from nixpkgs (skipped if already present)
5. Runs `home-manager switch --flake ~/git/dotfiles#<profile>` to activate the user environment

After the first successful run, `flake-rebuild` itself will be available in the host's fish shell for subsequent local deploys.

On non-NixOS Linux, Home Manager packages such as `qemu-user` only provide the emulator binary on the user PATH. Transparent execution of foreign ELF binaries during local Nix builds additionally requires host-level `binfmt_misc` registration and daemon-level `extra-platforms`, which are managed here through pyinfra rather than Home Manager.
