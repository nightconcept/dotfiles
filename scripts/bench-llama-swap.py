#!/usr/bin/env python3
"""Benchmark terra's llama-swap models after per-model warmup."""

from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any

BASE_URL = "http://127.0.0.1:8080"
DEFAULT_MODELS = ["qwen3-27b-dense", "qwen3-35b-mtp", "gemma-4-26b-mtp"]
DEFAULT_RUNS = 3
DEFAULT_MAX_TOKENS = 160
DEFAULT_WARMUP_MAX_TOKENS = 32
DEFAULT_TIMEOUT = 1800
ARTIFACT_ROOT = Path("/tmp/bench-llama-swap-results")

PROMPT = (
    "Explain, in technical depth, how speculative decoding interacts with KV cache "
    "precision, flash attention, batching, and long context limits. Keep the "
    "answer dense and practical."
)


@dataclass
class BenchResult:
    model: str
    warmup_elapsed: float
    runs: list[dict[str, Any]]


def post_json(path: str, payload: dict[str, Any], timeout: int) -> dict[str, Any]:
    body = json.dumps(payload).encode()
    request = urllib.request.Request(
        f"{BASE_URL}{path}",
        data=body,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read())


def get_json(path: str, timeout: int) -> dict[str, Any]:
    with urllib.request.urlopen(f"{BASE_URL}{path}", timeout=timeout) as response:
        return json.loads(response.read())


def chat_request(model: str, max_tokens: int, timeout: int, *, warmup: bool) -> tuple[dict[str, Any], float]:
    payload = {
        "model": model,
        "messages": [{"role": "user", "content": PROMPT if not warmup else "Reply with exactly: warm"}],
        "max_tokens": max_tokens,
        "temperature": 0,
        "chat_template_kwargs": {"enable_thinking": False},
    }
    started = time.time()
    response = post_json("/v1/chat/completions", payload, timeout)
    return response, time.time() - started


def benchmark_model(model: str, runs: int, max_tokens: int, warmup_max_tokens: int, timeout: int) -> BenchResult:
    print(f"\n[{model}] warming up...")
    _, warmup_elapsed = chat_request(model, warmup_max_tokens, timeout, warmup=True)
    print(f"  warmup: {warmup_elapsed:.2f}s")

    results: list[dict[str, Any]] = []
    for index in range(1, runs + 1):
        response, elapsed = chat_request(model, max_tokens, timeout, warmup=False)
        choice = response["choices"][0]
        usage = response.get("usage", {})
        completion_tokens = int(usage.get("completion_tokens", 0) or 0)
        tps = completion_tokens / elapsed if elapsed > 0 else 0.0
        results.append(
            {
                "run": index,
                "elapsed_sec": elapsed,
                "completion_tokens": completion_tokens,
                "tokens_per_sec": tps,
                "finish_reason": choice.get("finish_reason"),
            }
        )
        print(
            f"  run {index}/{runs}: elapsed={elapsed:.2f}s "
            f"completion={completion_tokens} tok tps={tps:.1f}"
        )
    return BenchResult(model=model, warmup_elapsed=warmup_elapsed, runs=results)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--models", nargs="*", default=DEFAULT_MODELS)
    parser.add_argument("--runs", type=int, default=DEFAULT_RUNS)
    parser.add_argument("--max-tokens", type=int, default=DEFAULT_MAX_TOKENS)
    parser.add_argument("--warmup-max-tokens", type=int, default=DEFAULT_WARMUP_MAX_TOKENS)
    parser.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT)
    args = parser.parse_args()

    ARTIFACT_ROOT.mkdir(parents=True, exist_ok=True)
    summary = {
        "timestamp": int(time.time()),
        "models": [],
        "available_models": get_json("/v1/models", args.timeout),
    }

    for model in args.models:
        result = benchmark_model(
            model,
            runs=args.runs,
            max_tokens=args.max_tokens,
            warmup_max_tokens=args.warmup_max_tokens,
            timeout=args.timeout,
        )
        avg_tps = sum(run["tokens_per_sec"] for run in result.runs) / len(result.runs)
        avg_elapsed = sum(run["elapsed_sec"] for run in result.runs) / len(result.runs)
        summary["models"].append(
            {
                "model": result.model,
                "warmup_elapsed_sec": result.warmup_elapsed,
                "avg_elapsed_sec": avg_elapsed,
                "avg_tokens_per_sec": avg_tps,
                "runs": result.runs,
            }
        )

    output_path = ARTIFACT_ROOT / f"bench-{int(time.time())}.json"
    output_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(f"\nresults: {output_path}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except urllib.error.HTTPError as exc:
        print(f"error: HTTP {exc.code} from llama-swap", file=sys.stderr)
        print(exc.read().decode("utf-8", errors="replace"), file=sys.stderr)
        raise
