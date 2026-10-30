"""Install the pinned Hermes runtime and connect its gateway to Terra's models."""

import io
import os
import shlex
from pathlib import Path

from pyinfra.operations import files, server, systemd

from modules.linux.ai.catalog import DEFAULT_MODEL_ID
from modules.linux.ai.versions import VERSIONS
from modules.linux.module import HostModule
from modules.linux.programs.foreman.module import gpu_window_open


class HermesModule(HostModule):
    """Manage Hermes code and dependencies while preserving persistent user state."""

    def __init__(self):
        """Initialize Hermes config path and target default model."""
        self.config_path = os.path.expanduser("~/.hermes/config.yaml")
        self.hermes_home = os.path.dirname(self.config_path)
        self.install_dir = f"{self.hermes_home}/hermes-agent"
        self.install_script = os.path.expanduser("~/.local/libexec/hermes-install")
        self.repo_root = Path(__file__).resolve().parents[3]
        # Keep in sync with the model llama-swap should serve by default.
        self.default_model = os.environ.get("HERMES_DEFAULT_MODEL", DEFAULT_MODEL_ID)

    def install(self):
        """Prepare the pinned checkout and locked environment only when needed."""
        files.directory(
            name="Ensure Hermes deployment helper directory exists",
            path=os.path.dirname(self.install_script),
        )
        files.put(
            name="Install the Hermes deployment helper",
            src=str(Path(__file__).with_name("hermes-install.sh")),
            dest=self.install_script,
            mode="755",
        )
        pin = VERSIONS["hermes"]
        command = shlex.join(
            [
                self.install_script,
                self.install_dir,
                pin["repo"],
                pin["commit"],
            ]
        )
        server.shell(
            name="Prepare the pinned Hermes runtime (backs up state before changes)",
            commands=[f"HERMES_HOME={shlex.quote(self.hermes_home)} {command}"],
        )
        local_bin = os.path.expanduser("~/.local/bin")
        files.directory(name="Ensure Hermes launcher directory exists", path=local_bin)
        launcher = (
            "#!/usr/bin/env bash\n"
            "unset PYTHONPATH PYTHONHOME\n"
            f'exec {shlex.quote(self.install_dir + "/.hermes/bin/hermes")} "$@"\n'
        )
        files.put(
            name="Install the pinned Hermes launcher",
            src=io.StringIO(launcher),
            dest=f"{local_bin}/hermes",
            mode="755",
        )

    def update(self):
        """Point Hermes's default model and Terra custom provider at the target model."""
        # While foreman's GPU window is open, llama-swap is down on purpose, so the check
        # would fail the deploy. The config update below does not need llama-swap.
        if not gpu_window_open():
            self._verify_llama_swap()
        server.shell(
            name=f"Point Hermes config at {self.default_model}",
            commands=[
                f"cd {self.repo_root} && uv run python scripts/update-hermes-model.py "
                f"--config {self.config_path} --model {self.default_model} --context 131072"
            ],
        )

    def _verify_llama_swap(self):
        """Fail the deploy unless llama-swap serves the default model."""
        probe = shlex.quote(
            "import json,os,sys; "
            "ids={m['id'] for m in json.load(sys.stdin)['data']}; "
            "sys.exit(os.environ['MODEL'] not in ids)"
        )
        server.shell(
            name=f"Verify llama-swap serves {self.default_model} before pointing Hermes at it",
            commands=[
                f"""
                set -eu
                export MODEL={shlex.quote(self.default_model)}
                # llama-swap.service is Type=simple: systemd marks it active as soon as the
                # process forks, before it has probed the GPU and bound its port. A restart
                # just ahead of this step can lose that race, so retry briefly instead of
                # failing on the first connection refusal.
                ok=0
                for attempt in $(seq 1 10); do
                    if curl -fsS http://127.0.0.1:8080/v1/models \
                            | python3 -c {probe} 2>/dev/null; then
                        ok=1
                        break
                    fi
                    sleep 1
                done
                if [ "$ok" -ne 1 ]; then
                    echo "llama-swap does not list '$MODEL'; Hermes config was not changed." >&2
                    echo "Rerun the full Terra deploy to apply ai/catalog.py." >&2
                    exit 1
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
        """Disable the gateway, keeping its checkout, environment, and user state."""
        systemd.service(
            name="Disable Hermes gateway without deleting user state",
            service="hermes-gateway",
            running=False,
            enabled=False,
            user_mode=True,
        )
