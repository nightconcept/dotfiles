"""Strata: the engine that serves Qwen3.8 Flash Next GSQ-RCO packs on terra.

Rebuilds what llama-swap's Strata entries need: the pinned Strata checkout, every pack's model
shards, and Strata's own setup (engine, venv, pack, MTP draft layer). It never deletes or
re-downloads model data. Shards already on the storage disk are moved or hard-linked into
place, and missing ones are downloaded with resumable aria2 (see fetch-shard.sh).
"""

import os

from pyinfra.operations import apt, files, server

from modules.linux.module import HostModule
from modules.linux.programs.model_catalog import (
    MODEL_DIR,
    STRATA_COMMIT,
    STRATA_DATA_DIR,
    STRATA_DIR,
    STRATA_REPO,
    STRATA_TAG,
    strata_models,
)

_FETCH_SCRIPT = os.path.join(os.path.dirname(__file__), "fetch-shard.sh")


class StrataModule(HostModule):
    """Clones Strata, puts the catalog's Strata shards in place, and prepares each pack."""

    def __init__(self, backend="hip", port=8081):
        """Initialize Strata paths.

        Args:
            backend: Strata GPU backend passed to setup.sh.
            port: Port written into run-<model>.sh; llama-swap passes its own port instead.
        """
        self.user = os.environ.get("USER", "danny")
        self.backend = backend
        self.port = port
        self.fetch_script = f"/home/{self.user}/.local/libexec/strata-fetch-shard"

    def install(self):
        """Install prerequisites and put Strata at the pinned release.

        A missing checkout is a shallow clone of the tag. A clean checkout on another commit is
        moved to the tag (setup then rebuilds the engine); one with local changes stops the deploy.
        """
        apt.packages(
            name="Install Strata prerequisites",
            packages=["git", "aria2", "python3-venv", "python3-pip"],
            _sudo=True,
        )
        server.shell(
            name=f"Fetch Strata {STRATA_TAG}",
            commands=[
                f"""
                set -eu
                if [ ! -d "{STRATA_DIR}/.git" ]; then
                    git clone --quiet --depth 1 --branch "{STRATA_TAG}" \\
                        "{STRATA_REPO}" "{STRATA_DIR}"
                fi
                cd "{STRATA_DIR}"
                if [ "$(git rev-parse HEAD)" != "{STRATA_COMMIT}" ]; then
                    if ! git diff --quiet || ! git diff --cached --quiet; then
                        echo "Strata has local changes; not moving it to {STRATA_TAG}." >&2
                        exit 1
                    fi
                    depth=""
                    [ -f .git/shallow ] && depth="--depth 1"
                    git fetch --quiet $depth origin "refs/tags/{STRATA_TAG}:refs/tags/{STRATA_TAG}"
                    git checkout --quiet "{STRATA_COMMIT}"
                fi
                """
            ],
        )

    def update(self):
        """Put every Strata shard in place, then run Strata's setup for each pack."""
        files.put(
            name="Install the Strata shard fetcher",
            src=_FETCH_SCRIPT,
            dest=self.fetch_script,
            mode="755",
        )
        for model in strata_models():
            pack = model["strata"]
            name = pack["model"]
            dest_dir = f"{STRATA_DATA_DIR}/models/{name}"
            base = f"https://huggingface.co/{pack['repo_id']}/resolve/{pack['revision']}/{name}"
            server.shell(
                name=f"Put Strata {name} shards in place (move or resume, never re-download)",
                commands=[
                    f'"{self.fetch_script}" "{dest_dir}" "{shard["name"]}" {shard["size"]} '
                    f'{shard["sha256"]} "{base}/{shard["name"]}" '
                    f'"{STRATA_DATA_DIR}/models" "{MODEL_DIR}"'
                    for shard in pack["shards"]
                ],
            )
            config = f"{STRATA_DIR}/strata-{name.lower()}.json"
            server.shell(
                name=f"Prepare the Strata {name} pack",
                commands=[
                    f'cd "{STRATA_DIR}" && ./setup.sh --yes --family qwen --model {name} '
                    f'--backend {self.backend} --data-dir "{STRATA_DATA_DIR}" --port {self.port} '
                    f"--context {model['context']} --no-browser --no-start "
                    f'>> "{STRATA_DIR}/strata-setup-{name.lower()}.log" 2>&1 '
                    f'|| {{ tail -20 "{STRATA_DIR}/strata-setup-{name.lower()}.log"; exit 1; }}',
                    f'test -f "{config}" || {{ echo "setup did not write {config}" >&2; exit 1; }}',
                ],
            )

    def remove(self):
        """Leave Strata and its model data in place; removing them is a manual step."""
