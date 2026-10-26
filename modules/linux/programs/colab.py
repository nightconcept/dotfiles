"""Google Colab CLI module for host configuration.

Installs google-colab-cli (https://github.com/googlecolab/google-colab-cli) as a uv
tool. Vesper drives Colab GPU runtimes from terra with it. The first run needs a
one-time OAuth login by the owner (copy-paste code flow, works over SSH); the
token lives in ~/.config/colab-cli/token.json and is never managed here.
"""

from pyinfra.operations import server

from modules.linux.module import HostModule

PACKAGE = "google-colab-cli"
MIN_VERSION = "0.7.5"


class ColabModule(HostModule):
    """Manages the Google Colab CLI installation and updates."""

    def install(self):
        """Verify uv is on the system and install google-colab-cli."""
        server.shell(
            name="Verify uv and install google-colab-cli",
            commands=[
                'command -v uv >/dev/null 2>&1 || { echo >&2 "uv required. Aborting."; exit 1; }',
                f"if ! uv tool list | grep -q '^{PACKAGE} '; then "
                f"uv tool install '{PACKAGE}>={MIN_VERSION}'; fi",
            ],
        )

    def update(self):
        """Upgrade google-colab-cli to the latest version."""
        server.shell(
            name="Upgrade google-colab-cli via uv",
            commands=[f"uv tool upgrade {PACKAGE}"],
        )

    def remove(self):
        """Uninstall google-colab-cli. The OAuth token in ~/.config/colab-cli stays."""
        server.shell(
            name="Remove google-colab-cli via uv",
            commands=[f"uv tool uninstall {PACKAGE}"],
        )
