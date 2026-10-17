"""Shared local LLM catalog for terra."""

from __future__ import annotations

import json
import shlex
from typing import Any

MODEL_DIR = "/mnt/storage/llm-models"
LLAMA_CPP_SERVER = "/opt/llama-cpp/llama-server"
# Strata serves Qwen3.8 Flash Next GSQ-RCO packs. modules/linux/programs/strata.py clones it,
# fetches the shards listed under each entry's "strata" key, and runs its setup.
STRATA_REPO = "https://github.com/Niko1221/Strata.git"
# EdeaBench v0.1 ran on this release. GitHub ships only Windows engines, so setup.sh compiles the
# Linux HIP engine for terra's card (gfx1201).
STRATA_TAG = "v0.1.44.1"
STRATA_COMMIT = "296b59d2f73c8f04a805df29c2fa97655adace78"
STRATA_DIR = "/home/danny/git/Strata"
STRATA_DATA_DIR = f"{MODEL_DIR}/Strata-data"
# EdeaBench v0.1 (2026-10-17): Flash Next IQ2_XS ties the 27B and IQ3_XXS in under half
# the 27B's time.
DEFAULT_MODEL_ID = "qwen3.8-flash-next-iq2_xs"
BENCHMARK_MODEL_IDS = [
    "qwen3.8-27b",
    "muse-glimmer-30b",
    "qwen3-35b-mtp",
]


MODEL_CATALOG: list[dict[str, Any]] = [
    {
        # Strata serves its own packs and needs the whole GPU; llama-swap stops other models first.
        # LD_LIBRARY_PATH is cleared so llama.cpp's libraries from the unit do not shadow Strata's.
        # Strata refuses unknown Host headers, and llama-swap passes the client's through.
        "id": "qwen3.8-flash-next-iq2_xs",
        "files": [],
        "cmd": (
            "env -u LD_LIBRARY_PATH STRATA_ALLOWED_HOSTS=terra,terra.nclabs.net,192.168.1.173 "
            f"sh -c 'cd {STRATA_DIR} && exec .venv/bin/python "
            "serve/server.py --engine strata --config strata-iq2_xs.json --port ${PORT}'"
        ),
        "aliases": ["Qwen3.8-Flash-Next-GSQ-RCO-IQ2_XS"],
        "context": 131072,
        "strata": {
            "model": "IQ2_XS",
            "repo_id": "ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-GGUF",
            "revision": "ed59f92082b1e93c0e96d60a8b11aab089b52f09",
            "shards": [
                {
                    "name": "Qwen3.8-Flash-Next-GSQ-RCO-IQ2_XS-00001-of-00002.gguf",
                    "size": 39225954592,
                    "sha256": "92cee27ae5bbadcd732416a0f7a7f0acc092399dbbe8f5a5efa707c2ec0a49d7",
                },
                {
                    # IQ3_XXS ships the same bytes as its 00002 shard under another name.
                    "name": "Qwen3.8-Flash-Next-GSQ-RCO-IQ2_XS-00002-of-00002.gguf",
                    "size": 28800138432,
                    "sha256": "316b46f3a2dbd68c900f43136ab9449f9dcc3725dfd8c794847c204bc161e113",
                },
            ],
        },
    },
    {
        "id": "qwen3.8-27b",
        "repo_id": "unsloth/Qwen3.8-27B-GGUF",
        "files": ["Qwen3.8-27B-UD-Q5_K_XL.gguf"],
        "args": [
            "-m",
            f"{MODEL_DIR}/Qwen3.8-27B-UD-Q5_K_XL.gguf",
            "-c",
            "131072",
            "-ngl",
            "all",
            "-fa",
            "on",
            "-ctk",
            "q8_0",
            "-ctv",
            "q8_0",
            "--jinja",
            "--spec-type",
            "draft-mtp,ngram-mod",
            "--spec-draft-n-max",
            "2",
            "-np",
            "1",
            "--host",
            "127.0.0.1",
            "--port",
            "${PORT}",
        ],
        "aliases": ["Qwen3.8-27B-UD-Q5_K_XL"],
        "context": 131072,
    },
    {
        "id": "qwen3-35b-mtp",
        "repo_id": "havenoammo/Qwen3.6-35B-A3B-MTP-GGUF",
        "files": ["Qwen3.6-35B-A3B-MTP-UD-Q5_K_XL.gguf"],
        "args": [
            "-m",
            f"{MODEL_DIR}/Qwen3.6-35B-A3B-MTP-UD-Q5_K_XL.gguf",
            "-c",
            "131072",
            "-ngl",
            "all",
            "-fa",
            "on",
            "-ctk",
            "q8_0",
            "-ctv",
            "q8_0",
            "--no-mmproj",
            "--jinja",
            "--spec-type",
            "draft-mtp",
            "--spec-draft-n-max",
            "3",
            "--host",
            "127.0.0.1",
            "--port",
            "${PORT}",
        ],
        "aliases": ["Qwen3.6-35B-A3B-MTP-UD-Q5_K_XL"],
        "context": 131072,
    },
    {
        "id": "muse-glimmer-30b",
        "repo_id": "unsloth/Muse-Glimmer-30B-GGUF",
        "files": ["Muse-Glimmer-30B-UD-Q4_K_XL.gguf"],
        "args": [
            "-m",
            f"{MODEL_DIR}/Muse-Glimmer-30B-UD-Q4_K_XL.gguf",
            "-c",
            "131072",
            "-ngl",
            "all",
            "-fa",
            "on",
            "-ctk",
            "q8_0",
            "-ctv",
            "q8_0",
            "--no-mmproj",
            "--jinja",
            "--host",
            "127.0.0.1",
            "--port",
            "${PORT}",
        ],
        "aliases": ["Muse-Glimmer-30B-UD-Q4_K_XL"],
        "context": 131072,
    },
]


def catalog_entries() -> list[dict[str, Any]]:
    """Return flattened file entries for deployment."""
    entries: list[dict[str, Any]] = []
    for model in MODEL_CATALOG:
        for filename in model["files"]:
            entry: dict[str, Any] = {"filename": filename}
            if "repo_id" in model:
                entry["repo_id"] = model["repo_id"]
            if "local_sources" in model and filename in model["local_sources"]:
                entry["local_source"] = model["local_sources"][filename]
            entries.append(entry)
    return entries


def render_llama_swap_config() -> str:
    """Render a llama-swap YAML config for terra."""
    lines = [
        "healthCheckTimeout: 900",
        "logLevel: info",
        'logToStdout: "proxy"',
        "performance:",
        "  disabled: false",
        "  every: 15s",
        "startPort: 10001",
        "globalTTL: 0",
        "models:",
    ]

    for model in MODEL_CATALOG:
        cmd = model.get("cmd") or " ".join(
            shlex.quote(part) if part != "${PORT}" else part
            for part in [LLAMA_CPP_SERVER, *model["args"]]
        )
        capabilities = model.get("capabilities", {"in": ["text"], "out": ["text"]})
        lines.extend(
            [
                f'  "{model["id"]}":',
                f"    cmd: {json.dumps(cmd)}",
                '    proxy: "http://127.0.0.1:${PORT}"',
                f"    aliases: {json.dumps(model.get('aliases', []))}",
                "    capabilities:",
                f"      in: {json.dumps(capabilities['in'])}",
                f"      out: {json.dumps(capabilities['out'])}",
                "      tools: true",
                f"      context: {model['context']}",
            ]
        )

    return "\n".join(lines) + "\n"


def strata_models() -> list[dict[str, Any]]:
    """Return the catalog entries served by Strata."""
    return [model for model in MODEL_CATALOG if "strata" in model]
