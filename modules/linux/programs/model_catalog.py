"""Shared local LLM catalog for terra."""

from __future__ import annotations

import json
import shlex
from typing import Any

MODEL_DIR = "/mnt/storage/llm-models"
LLAMA_CPP_SERVER = "/opt/llama-cpp/llama-server"


MODEL_CATALOG: list[dict[str, Any]] = [
    {
        "id": "qwen3-27b-dense",
        "files": ["Qwen3.6-27B-Q6_K.gguf"],
        "local_sources": {
            "Qwen3.6-27B-Q6_K.gguf": f"{MODEL_DIR}/Qwen3.6-27B-Q6_K.gguf",
        },
        "args": [
            "-m",
            f"{MODEL_DIR}/Qwen3.6-27B-Q6_K.gguf",
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
        "aliases": ["Qwen3.6-27B-Q6_K"],
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
        "files": [
            "Muse-Glimmer-30B-UD-Q4_K_XL.gguf",
            "dflash-kquant.gguf",
            "mmproj-kquant.gguf",
        ],
        "args": [
            "-m",
            f"{MODEL_DIR}/Muse-Glimmer-30B-UD-Q4_K_XL.gguf",
            "-md",
            f"{MODEL_DIR}/dflash-kquant.gguf",
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
            "--spec-type",
            "draft-dflash",
            "--spec-draft-n-max",
            "8",
            "--mmproj",
            f"{MODEL_DIR}/mmproj-kquant.gguf",
            "--jinja",
            "--host",
            "127.0.0.1",
            "--port",
            "${PORT}",
        ],
        "aliases": ["Muse-Glimmer-30B-DFlash"],
        "context": 131072,
        "capabilities": {"in": ["text", "image"], "out": ["text"]},
    },
    {
        "id": "gemma-4-26b-mtp",
        "repo_id": "ironbcc/gemma-4-26B-A4B-it-MTP-GGUF",
        "files": [
            "gemma-4-26B-A4B-it-Q8_0.gguf",
            "gemma-4-26B-A4B-it-assistant-Q2_K.gguf",
        ],
        "local_sources": {
            "gemma-4-26B-A4B-it-Q8_0.gguf": f"{MODEL_DIR}/gemma-4-26B-A4B-it-Q8_0.gguf",
        },
        "args": [
            "-m",
            f"{MODEL_DIR}/gemma-4-26B-A4B-it-Q8_0.gguf",
            "-md",
            f"{MODEL_DIR}/gemma-4-26B-A4B-it-assistant-Q2_K.gguf",
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
        "aliases": ["gemma-4-26B-A4B-it-MTP-GGUF"],
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
        cmd = " ".join(
            shlex.quote(part) if part != "${PORT}" else part for part in [LLAMA_CPP_SERVER, *model["args"]]
        )
        capabilities = model.get("capabilities", {"in": ["text"], "out": ["text"]})
        lines.extend(
            [
                f'  "{model["id"]}":',
                f"    cmd: {json.dumps(cmd)}",
                f'    proxy: "http://127.0.0.1:${{PORT}}"',
                f"    aliases: {json.dumps(model.get('aliases', []))}",
                "    capabilities:",
                f"      in: {json.dumps(capabilities['in'])}",
                f"      out: {json.dumps(capabilities['out'])}",
                "      tools: true",
                f"      context: {model['context']}",
            ]
        )

    return "\n".join(lines) + "\n"
