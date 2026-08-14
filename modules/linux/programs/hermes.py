"""Hermes gateway sync hook for terra.

Hermes itself (~/.hermes) is not dotfiles-managed — it's installed and
configured independently. This module only owns keeping it pointed at
terra's local LLM stack: llama-swap serves models over an OpenAI-compatible
endpoint that Hermes connects to, so a config or model catalog change needs
Hermes's config updated and the gateway restarted to take effect.
"""

import os

from pyinfra.operations import server, systemd

from modules.linux.module import HostModule


class HermesModule(HostModule):
    """Points Hermes at the default model and restarts hermes-gateway."""

    def __init__(self):
        """Initialize Hermes config path and target default model."""
        self.config_path = os.path.expanduser("~/.hermes/config.yaml")
        # Keep in sync with the model llama-swap should serve by default.
        self.default_model = os.environ.get("HERMES_DEFAULT_MODEL", "muse-glimmer-30b")

    def install(self):
        """Nothing to install; Hermes is managed outside dotfiles."""
        pass

    def update(self):
        """Point Hermes's default model and Terra custom provider at the target model."""
        model = self.default_model
        default_expr = f"s/^  default: .*/  default: {model}/"
        provider_expr = (
            f"/^- name: Terra:8080$/,/^context_length:/{{s/^  model: .*/  model: {model}/}}"
        )
        server.shell(
            name=f"Point Hermes config at {model}",
            commands=[
                f"""
                set -eu
                CONFIG="{self.config_path}"
                if [ -f "$CONFIG" ]; then
                    sed -i -e '{default_expr}' -e '{provider_expr}' "$CONFIG"
                fi
                """
            ],
        )

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
        """Nothing to remove; Hermes is managed outside dotfiles."""
        pass
