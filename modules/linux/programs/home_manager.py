"""Home Manager module for non-NixOS Linux hosts."""

from pyinfra.operations import apt, server

from modules.linux.module import HostModule

DOTFILES_REPO = "https://forge.solivan.dev/nightconcept/dotfiles.git"
DOTFILES_DIR = "$HOME/git/dotfiles"
NIX_PROFILE = "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"


class HomeManagerModule(HostModule):
    """Installs Nix and home-manager, then applies the host's home-manager config."""

    def __init__(self, profile: str):
        self.profile = profile

    def install(self):
        apt.packages(
            name="Ensure git and curl are installed",
            packages=["git", "curl", "xz-utils"],
            _sudo=True,
        )

        server.shell(
            name="Install Nix (Determinate Systems)",
            commands=[
                "if ! command -v nix >/dev/null 2>&1; then "
                'curl --proto "=https" --tlsv1.2 -sSf -L https://install.determinate.systems/nix '
                "| sh -s -- install --no-confirm; fi"
            ],
        )

        server.shell(
            name="Clone dotfiles repository",
            commands=[
                f'if [ ! -d "{DOTFILES_DIR}/.git" ]; then '
                'mkdir -p "$HOME/git" && '
                f"git clone {DOTFILES_REPO} {DOTFILES_DIR}; fi"
            ],
        )

        server.shell(
            name="Install home-manager",
            commands=[
                f". {NIX_PROFILE} && "
                "if ! command -v home-manager >/dev/null 2>&1; then "
                "nix profile install nixpkgs#home-manager; fi"
            ],
        )

    def update(self):
        server.shell(
            name="Update dotfiles repository",
            commands=[f"git -C {DOTFILES_DIR} pull --ff-only"],
        )

        server.shell(
            name=f"Apply home-manager config for {self.profile}",
            commands=[
                f". {NIX_PROFILE} && "
                f"home-manager switch --flake {DOTFILES_DIR}#{self.profile} --impure"
            ],
        )

    def service(self):
        pass

    def remove(self):
        pass
