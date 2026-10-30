#!/usr/bin/env python3
"""Measure Terra's production inference endpoint without changing its services."""

from __future__ import annotations

import argparse
import datetime
import json
import os
import re
import subprocess
import sys
import time
import urllib.request
from collections.abc import Iterable
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT))

from modules.linux.ai.catalog import DEFAULT_MODEL_ID, MODEL_CATALOG  # noqa: E402

FIXTURE = "bench-fixture-47"
TOOL = {
    "type": "function",
    "function": {
        "name": "read_benchmark_fixture",
        "description": "Read the benchmark's fixed, synthetic fixture.",
        "parameters": {
            "type": "object",
            "properties": {"key": {"type": "string", "enum": ["marker"]}},
            "required": ["key"],
            "additionalProperties": False,
        },
    },
}


def git_output(path: Path, *args: str) -> str:
    """Read Git metadata without printing repository contents."""
    return subprocess.check_output(["git", "-C", str(path), *args], text=True).strip()


def preflight() -> dict[str, Any]:
    """Require clean installed sources and an inference GPU window."""
    foreman = subprocess.check_output(
        [str(Path.home() / ".local/bin/foreman"), "status", "--json"], text=True
    )
    status = json.loads(foreman)
    if status.get("gpu_leases") is not False:
        raise RuntimeError("Foreman GPU leases are active or status is unknown")
    sources = {}
    generated_artifact_counts = {}
    for name, path in {
        "strata": Path.home() / "git/Strata",
        "hermes": Path.home() / ".hermes/hermes-agent",
    }.items():
        # These deployment/download artifacts are not runtime source. All tracked
        # edits and other untracked paths still fail the clean-source check.
        allowed = (
            {
                "?? strata-downloads-iq3xxs.txt",
                "?? strata-downloads.txt",
                "?? strata-iq2_xs.json.bak",
            }
            if name == "strata"
            else set()
        )
        dirty = git_output(path, "status", "--porcelain").splitlines()
        if any(line not in allowed for line in dirty):
            raise RuntimeError(f"Installed {name} source is dirty; resolve before benchmarking")
        generated_artifact_counts[name] = len(dirty)
        sources[name] = git_output(path, "rev-parse", "HEAD")
    config_path = Path.home() / "git/Strata/strata-iq2_xs.json"
    config = json.loads(config_path.read_text())
    # Allowlist only inference settings. Never read Hermes personal config or credentials.
    settings = {key: config[key] for key in ("args", "backend", "model_name") if key in config}
    return {
        "installed_commits": sources,
        "strata_settings": settings,
        "untracked_generated_artifact_counts": generated_artifact_counts,
    }


def collect_stream(lines: Iterable[bytes], started: float) -> dict[str, Any]:
    """Collect OpenAI SSE deltas and preserve server usage and timing fields."""
    content = ""
    reasoning = ""
    calls: dict[int, dict[str, Any]] = {}
    usage = None
    timings = None
    first = None
    finish = None
    done = False
    for raw in lines:
        if not raw.startswith(b"data:"):
            continue
        data = raw[5:].strip()
        if data == b"[DONE]":
            done = True
            break
        chunk = json.loads(data)
        if "error" in chunk:
            raise RuntimeError("Endpoint returned an error in the event stream")
        usage = chunk.get("usage") or usage
        timings = chunk.get("timings") or timings
        for choice in chunk.get("choices", []):
            delta = choice.get("delta", {})
            if first is None and any(
                delta.get(key) for key in ("content", "reasoning_content", "tool_calls")
            ):
                first = time.monotonic() - started
            content += delta.get("content") or ""
            reasoning += delta.get("reasoning_content") or ""
            for call in delta.get("tool_calls") or []:
                current = calls.setdefault(
                    call["index"],
                    {"id": "", "type": "function", "function": {"name": "", "arguments": ""}},
                )
                current["id"] = call.get("id") or current["id"]
                for key in ("name", "arguments"):
                    current["function"][key] += call.get("function", {}).get(key) or ""
            finish = choice.get("finish_reason") or finish
    if not done or finish is None:
        raise RuntimeError("Incomplete SSE response")
    message: dict[str, Any] = {"role": "assistant", "content": content or None}
    if reasoning:
        message["reasoning_content"] = reasoning
    if calls:
        message["tool_calls"] = [calls[index] for index in sorted(calls)]
    return {
        "message": message,
        "finish_reason": finish,
        "usage": usage,
        "timings": timings,
        "latency_s": time.monotonic() - started,
        # First visible/reasoning/tool delta, not a tokenizer-level token measurement.
        "ttft_s": first,
        "decode_tokens_per_second": (timings or {}).get("predicted_per_second"),
    }


def completion(url: str, payload: dict[str, Any], timeout: int) -> dict[str, Any]:
    """Send one streaming request and time it from before opening HTTP."""
    request = urllib.request.Request(
        url.rstrip("/") + "/chat/completions",
        data=json.dumps(
            {**payload, "stream": True, "stream_options": {"include_usage": True}}
        ).encode(),
        headers={"Content-Type": "application/json"},
    )
    started = time.monotonic()
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return collect_stream(response, started)


def fixture_result(message: dict[str, Any]) -> dict[str, str]:
    """Validate the requested fixture read without executing generated code."""
    calls = message.get("tool_calls", [])
    if len(calls) != 1:
        raise ValueError("Expected exactly one fixture call")
    call = calls[0]
    function = call["function"]
    if (
        not call.get("id")
        or function["name"] != "read_benchmark_fixture"
        or json.loads(function["arguments"]) != {"key": "marker"}
    ):
        raise ValueError("Invalid fixture call")
    return {"role": "tool", "tool_call_id": call["id"], "content": FIXTURE}


def run_cases(args: argparse.Namespace, artifact: Path) -> bool:
    """Run warmup, repeated text cases, and a complete synthetic tool roundtrip."""
    base = {
        "model": args.model,
        "temperature": 0,
        "max_tokens": 256,
        "chat_template_kwargs": {"enable_thinking": False},
    }
    cases = {
        "short": "Reply with exactly: BENCH_OK",
        "decode": (
            "Write a 220-word technical explanation of a fictional rain sensor. "
            "Include its calibration, sampling, and fault detection. Use plain prose."
        ),
        "long": (
            "Read the fixture records below. Return only the marker in the final record.\n"
            + "\n".join(f"record {i:04d}: status normal; marker absent." for i in range(512))
            + "\nfinal record: marker BENCH_OK"
        ),
    }
    passed = True
    with (artifact / "results.jsonl").open("x") as handle:

        def record(case: str, sample: int, **extra: Any) -> None:
            handle.write(json.dumps({"case": case, "sample": sample, **extra}) + "\n")
            handle.flush()

        warmup = completion(
            args.url,
            {**base, "messages": [{"role": "user", "content": cases["short"]}]},
            args.timeout,
        )
        record("warmup", 0, **warmup)
        for sample in range(args.samples):
            for name, prompt in cases.items():
                result = completion(
                    args.url,
                    {**base, "messages": [{"role": "user", "content": prompt}]},
                    args.timeout,
                )
                success = (
                    bool(result["message"]["content"]) and not result["message"].get("tool_calls")
                    if name == "decode"
                    else result["message"]["content"] == "BENCH_OK"
                )
                record(name, sample, success=success, **result)
                passed = passed and success
            messages = [
                {
                    "role": "user",
                    "content": "Read the marker fixture with the tool. "
                    "Then reply with exactly its returned value.",
                }
            ]
            first = completion(
                args.url,
                {
                    **base,
                    "messages": messages,
                    "tools": [TOOL],
                    "tool_choice": {
                        "type": "function",
                        "function": {"name": "read_benchmark_fixture"},
                    },
                },
                args.timeout,
            )
            try:
                tool_result = fixture_result(first["message"])
            except (ValueError, KeyError, TypeError):
                record("tool_call", sample, success=False, **first)
                passed = False
                continue
            record("tool_call", sample, success=True, **first)
            final = completion(
                args.url,
                {
                    **base,
                    "messages": [*messages, first["message"], tool_result],
                    "tools": [TOOL],
                    "tool_choice": "none",
                },
                args.timeout,
            )
            success = final["message"]["content"] == FIXTURE
            record("tool_result", sample, success=success, **final)
            passed = passed and success
    return passed


def main() -> int:
    """Write a labeled private benchmark artifact and return validation status."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--label", required=True, help="Comparison label, e.g. before or after")
    parser.add_argument("--url", default="http://127.0.0.1:8080/v1")
    parser.add_argument("--model", default=DEFAULT_MODEL_ID)
    parser.add_argument("--samples", type=int, default=3)
    parser.add_argument("--timeout", type=int, default=900)
    parser.add_argument("--output", type=Path, default=Path.home() / ".local/state/ai-bench")
    args = parser.parse_args()
    if not re.fullmatch(r"[a-zA-Z0-9_-]+", args.label) or args.samples < 1:
        parser.error("Use a simple label and a positive sample count")
    os.umask(0o077)
    metadata = preflight()
    selected = next((item for item in MODEL_CATALOG if item["id"] == args.model), None)
    if selected is None:
        parser.error("Model must exist in the catalog")
    metadata.update(
        model=selected,
        url=args.url,
        samples=args.samples,
        harness_commit=git_output(REPO_ROOT, "rev-parse", "HEAD"),
    )
    stamp = datetime.datetime.now(datetime.UTC).strftime("%Y%m%dT%H%M%S%fZ")
    artifact = args.output / f"{stamp}-{args.label}"
    artifact.mkdir(parents=True, mode=0o700)
    (artifact / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(f"Artifacts: {artifact}", flush=True)
    try:
        passed = run_cases(args, artifact)
    except Exception as error:
        # The artifact contains only synthetic responses; do not print arbitrary HTTP bodies.
        (artifact / "error.json").write_text(json.dumps({"type": type(error).__name__}))
        print(f"Benchmark interrupted: {type(error).__name__}", file=sys.stderr)
        return 1
    print("Checks passed" if passed else "One or more output checks failed")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
