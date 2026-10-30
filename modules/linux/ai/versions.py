"""Load the AI stack's committed software pins."""

import re
import tomllib
from pathlib import Path
from typing import Any


def load_versions(path: Path | None = None) -> dict[str, Any]:
    """Read software pins and reject mutable Git revisions."""
    manifest = path or Path(__file__).with_name("versions.toml")
    with manifest.open("rb") as source:
        versions = tomllib.load(source)
    for name in ("llama_cpp", "strata", "hermes"):
        if not re.fullmatch(r"[0-9a-f]{40}", versions[name]["commit"]):
            raise ValueError(f"{name} must pin a full Git commit")
    return versions


VERSIONS = load_versions()
