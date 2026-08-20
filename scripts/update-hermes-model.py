#!/usr/bin/env python3
"""Atomically update Hermes's Terra model selection and context."""

from __future__ import annotations

import argparse
import os
import tempfile
from pathlib import Path
from typing import Any

import yaml


def update_config(config: dict[str, Any], model: str, context: int) -> None:
    """Update both Hermes model references and enforce the Terra context."""
    model_config = config.get("model")
    if not isinstance(model_config, dict):
        raise ValueError("Hermes config has no model mapping")
    model_config["default"] = model

    providers = config.get("custom_providers")
    if not isinstance(providers, list):
        raise ValueError("Hermes config has no custom_providers list")
    for provider in providers:
        if isinstance(provider, dict) and provider.get("name") == "Terra:8080":
            provider["model"] = model
            provider["context_length"] = context
            return
    raise ValueError("Hermes config has no Terra:8080 provider")


def atomic_update(path: Path, model: str, context: int) -> None:
    """Parse, update, validate, and atomically replace a Hermes YAML file."""
    original = path.read_text(encoding="utf-8")
    config = yaml.safe_load(original)
    if not isinstance(config, dict):
        raise ValueError("Hermes config root is not a mapping")
    update_config(config, model, context)

    rendered = yaml.safe_dump(config, sort_keys=False, allow_unicode=True)
    validated = yaml.safe_load(rendered)
    if not isinstance(validated, dict):
        raise ValueError("rendered Hermes config is invalid")

    file_descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary_path = Path(temporary_name)
    try:
        with os.fdopen(file_descriptor, "w", encoding="utf-8") as temporary_file:
            temporary_file.write(rendered)
            temporary_file.flush()
            os.fsync(temporary_file.fileno())
        os.chmod(temporary_path, path.stat().st_mode)
        os.replace(temporary_path, path)
    finally:
        temporary_path.unlink(missing_ok=True)


def main() -> int:
    """Parse command-line arguments and update the requested config."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--context", type=int, default=131072)
    args = parser.parse_args()
    atomic_update(args.config, args.model, args.context)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
