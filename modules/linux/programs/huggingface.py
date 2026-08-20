"""HuggingFace module for host configuration."""

from pyinfra.operations import server

from modules.linux.module import HostModule


class HuggingFaceModule(HostModule):
    """Manages HuggingFace tools installation and updates."""

    def install(self):
        """Verify uv is on system and install huggingface_hub."""
        server.shell(
            name="Verify uv and install huggingface_hub",
            commands=[
                'command -v uv >/dev/null 2>&1 || { echo >&2 "uv required. Aborting."; exit 1; }',
                "if ! uv tool list | grep -q huggingface_hub; then "
                "uv tool install huggingface_hub; fi",
            ],
        )

    def update(self):
        """Upgrade huggingface_hub to the latest version."""
        server.shell(
            name="Upgrade huggingface_hub via uv",
            commands=["uv tool upgrade huggingface_hub"],
        )

    def remove(self):
        """Uninstall huggingface_hub."""
        server.shell(
            name="Remove huggingface_hub via uv",
            commands=["uv tool uninstall huggingface_hub"],
        )
