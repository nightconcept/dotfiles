"""Hermes gateway restart hook for terra.

Hermes itself (~/.hermes) is not dotfiles-managed — it's installed and
configured independently. This module only owns keeping its systemd --user
service in sync with terra's local LLM stack: llama-swap serves models over
an OpenAI-compatible endpoint that Hermes connects to, so a config or model
catalog change needs Hermes to reconnect to take effect.
"""

from pyinfra.operations import systemd

from modules.linux.module import HostModule


class HermesModule(HostModule):
    """Restarts the hermes-gateway user service on every deploy."""

    def install(self):
        pass

    def update(self):
        pass

    def service(self):
        """Restart hermes-gateway so it never keeps using a stale connection."""
        systemd.service(
            name="Restart hermes-gateway to pick up llama-swap changes",
            service="hermes-gateway",
            running=True,
            restarted=True,
            user_mode=True,
        )

    def remove(self):
        pass
