"""Hermes gateway sync hook for terra.

Hermes itself (~/.hermes) is not dotfiles-managed — it's installed and
configured independently. This module only owns keeping it pointed at
terra's local LLM stack: llama-swap serves models over an OpenAI-compatible
endpoint that Hermes connects to, so a config or model catalog change needs
Hermes's config updated and the gateway restarted to take effect.
"""

import os
from pathlib import Path

from pyinfra.operations import server, systemd

from modules.linux.module import HostModule
from modules.linux.programs.model_catalog import DEFAULT_MODEL_ID


class HermesModule(HostModule):
    """Points Hermes at the default model and restarts hermes-gateway."""

    def __init__(self):
        """Initialize Hermes config path and target default model."""
        self.config_path = os.path.expanduser("~/.hermes/config.yaml")
        self.repo_root = Path(__file__).resolve().parents[3]
        # Keep in sync with the model llama-swap should serve by default.
        self.default_model = os.environ.get("HERMES_DEFAULT_MODEL", DEFAULT_MODEL_ID)

    def install(self):
        """Nothing to install; Hermes is managed outside dotfiles."""
        pass

    def update(self):
        """Point Hermes's default model and Terra custom provider at the target model."""
        server.shell(
            name=f"Verify llama-swap serves {self.default_model} before pointing Hermes at it",
            commands=[
                f"""
                set -eu
                MODEL={self.default_model!r}
                # llama-swap.service is Type=simple: systemd marks it active as soon as the
                # process forks, before it has probed the GPU and bound its port. A restart
                # just ahead of this step can lose that race, so retry briefly instead of
                # failing on the first connection refusal.
                ok=0
                for attempt in $(seq 1 10); do
                    if curl -fsS http://127.0.0.1:8080/v1/models \
                            | python3 -c "import json,sys; ids={{m['id'] for m in json.load(sys.stdin)['data']}}; sys.exit(0 if '$MODEL' in ids else 1)" 2>/dev/null; then
                        ok=1
                        break
                    fi
                    sleep 1
                done
                if [ "$ok" -ne 1 ]; then
                    echo "llama-swap is not serving model '$MODEL' — refusing to point Hermes at it." >&2
                    echo "Redeploy llama_swap (render_llama_swap_config) so its catalog matches model_catalog.py first." >&2
                    exit 1
                fi
                """
            ],
        )
        server.shell(
            name=f"Point Hermes config at {self.default_model}",
            commands=[
                f"cd {self.repo_root} && uv run python scripts/update-hermes-model.py "
                f"--config {self.config_path} --model {self.default_model} --context 131072"
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
