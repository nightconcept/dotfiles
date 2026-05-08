"""LLM models management module for host configuration."""

import os

from pyinfra.operations import files, server

from ..module import HostModule

# Add models here. Format: (repo_id, filename)
MODEL_MANIFEST = [
    ("unsloth/Qwen3.6-35B-A3B-GGUF", "Qwen3.6-35B-A3B-UD-Q5_K_XL.gguf"),
]


class LLMModelsModule(HostModule):
    """Manages LLM models installation and cleanup in a default location."""

    def __init__(self):
        """Initialize model paths."""
        self.model_dir = "/opt/llm-models"
        self.user = os.environ.get("USER", "danny")

    def install(self):
        """Ensure model directory exists with correct ownership."""
        files.directory(
            name=f"Ensure {self.model_dir} exists with correct ownership",
            path=self.model_dir,
            present=True,
            user=self.user,
            group=self.user,
            _sudo=True,
        )

    def update(self):
        """Download models listed in the manifest using hf cli."""
        for repo_id, filename in MODEL_MANIFEST:
            # We check if file exists to avoid slow hf calls if already present
            server.shell(
                name=f"Download {filename}",
                commands=[
                    f"if [ ! -f {self.model_dir}/{filename} ]; then "
                    f"hf download {repo_id} {filename} "
                    f"--local-dir {self.model_dir} </dev/null; fi"
                ],
            )

    def cleanup(self):
        """Delete models in the target folder that are not in the manifest."""
        allowed_files = [m[1] for m in MODEL_MANIFEST]
        allowed_files.append("VERSION")

        # Join for shell regex/grep
        allowed_pattern = "|".join(allowed_files)

        server.shell(
            name="Cleanup unused models",
            commands=[
                f"find {self.model_dir} -maxdepth 1 -type f ! -name '.*' | "
                f"while read -r file; do "
                f"  base=$(basename \"$file\"); "
                f"  if ! echo \"$base\" | grep -qE '^({allowed_pattern})$'; then "
                f"    echo \"Removing unlisted model: $base\"; "
                f"    rm \"$file\"; "
                f"  fi; "
                f"done"
            ],
        )

    def remove(self):
        """Remove all managed models and the directory."""
        files.directory(
            name=f"Remove {self.model_dir}",
            path=self.model_dir,
            present=False,
            _sudo=True,
        )
