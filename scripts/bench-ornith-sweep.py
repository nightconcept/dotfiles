#!/usr/bin/env python3
"""Sweep Ornith-1.5-35B-A3B across speculative-decoding configs and compare tok/s.

Appends to the same ~/.hermes/benchmarks/results.jsonl as bench-speed.py, using
an identical fingerprint scheme, so re-running this script only retests configs
that aren't already recorded.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import signal
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT))

from modules.linux.programs.model_catalog import (  # noqa: E402
    DEFAULT_MODEL_ID,
    LLAMA_CPP_SERVER,
    MODEL_DIR,
)

LLAMA_SWAP_URL = "http://127.0.0.1:8080"
DEFAULT_SPEED_BENCH = Path(
    "/home/danny/git/llama.cpp/tools/server/bench/speed-bench/speed_bench.py"
)
DEFAULT_RESTORE_MODEL = DEFAULT_MODEL_ID
DEFAULT_ARTIFACT_ROOT = Path.home() / ".hermes" / "benchmarks"
RESULTS_JSONL = DEFAULT_ARTIFACT_ROOT / "results.jsonl"
DEFAULT_CATEGORIES = "coding,reasoning,summarization,writing"
DEFAULT_OUTPUT_TOKENS = 256
DEFAULT_SAMPLES_PER_CATEGORY = 5
DEFAULT_CONCURRENCY = 1
SERVER_PORT = 18080
SERVER_URL = f"http://127.0.0.1:{SERVER_PORT}"
SERVER_TIMEOUT = 900
BENCH_TIMEOUT = 900
SERVER_ENV = {
    **os.environ,
    "ROCM_PATH": "/opt/rocm",
    "LD_LIBRARY_PATH": "/opt/llama-cpp:/opt/rocm/lib:/opt/rocm/lib64",
}

MODEL_ID = "ornith-1.5-35b-a3b"
MODEL_PATH = Path(MODEL_DIR) / "Ornith-1.5-35B-A3B-Q4_K_M.gguf"
BASE_ARGS = [
    "-m",
    str(MODEL_PATH),
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
    str(SERVER_PORT),
]

# Named speculative-decoding configs to compare against the no-spec-decode baseline.
SWEEP_CONFIGS: list[tuple[str, list[str]]] = [
    ("baseline", []),
    ("mtp-2", ["--spec-type", "draft-mtp", "--spec-draft-n-max", "2"]),
    ("mtp-3", ["--spec-type", "draft-mtp", "--spec-draft-n-max", "3"]),
    ("mtp-4", ["--spec-type", "draft-mtp", "--spec-draft-n-max", "4"]),
    ("mtp-6", ["--spec-type", "draft-mtp", "--spec-draft-n-max", "6"]),
    (
        "mtp-3-pmin50",
        ["--spec-type", "draft-mtp", "--spec-draft-n-max", "3", "--spec-draft-p-min", "0.5"],
    ),
    (
        "mtp-3-pmin75",
        ["--spec-type", "draft-mtp", "--spec-draft-n-max", "3", "--spec-draft-p-min", "0.75"],
    ),
    (
        "mtp-6-pmin75",
        ["--spec-type", "draft-mtp", "--spec-draft-n-max", "6", "--spec-draft-p-min", "0.75"],
    ),
]


def request(path: str, *, payload: dict[str, Any] | None = None, timeout: int = 30) -> Any:
    """Send a JSON request to llama-swap."""
    data = json.dumps(payload).encode() if payload is not None else b""
    method = "POST" if payload is not None or path.startswith("/api/") else "GET"
    req = urllib.request.Request(
        f"{LLAMA_SWAP_URL}{path}",
        data=data if method == "POST" else None,
        headers={"Content-Type": "application/json"},
        method=method,
    )
    with urllib.request.urlopen(req, timeout=timeout) as response:
        body = response.read()
    return json.loads(body) if body else None


def unload_backend() -> None:
    """Stop every llama-server child without stopping llama-swap itself."""
    request("/api/models/unload")
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        running = request("/running")
        if not running.get("running", []):
            return
        time.sleep(0.25)
    raise RuntimeError("llama-swap did not unload its backend within 30 seconds")


def restore_backend(model: str) -> None:
    """Load the production model through llama-swap before Hermes restarts."""
    payload = {
        "model": model,
        "messages": [{"role": "user", "content": "Reply with exactly: ready"}],
        "max_tokens": 8,
        "temperature": 0,
        "chat_template_kwargs": {"enable_thinking": False},
    }
    request("/v1/chat/completions", payload=payload, timeout=SERVER_TIMEOUT)
    running = request("/running")
    running_models = [item.get("model") or item.get("id") for item in running.get("running", [])]
    if model not in running_models and model not in json.dumps(running):
        raise RuntimeError(f"llama-swap did not report {model!r} as running: {running}")


def config_fingerprint(
    model_id: str,
    model_path: Path,
    server_args: list[str],
    categories: str,
    output_tokens: int,
    samples_per_category: int,
    concurrency: int,
) -> str:
    """Match bench-speed.py's fingerprint scheme so shared history dedupes correctly."""
    stat = model_path.stat()
    payload = {
        "model_id": model_id,
        "model_path": str(model_path),
        "model_size": stat.st_size,
        "model_mtime": int(stat.st_mtime),
        "server_args": server_args,
        "categories": categories,
        "output_tokens": output_tokens,
        "samples_per_category": samples_per_category,
        "concurrency": concurrency,
    }
    digest = hashlib.sha256(json.dumps(payload, sort_keys=True).encode()).hexdigest()
    return digest[:16]


def load_tested_fingerprints(results_jsonl: Path) -> set[str]:
    """Read every fingerprint already recorded in the results JSONL."""
    if not results_jsonl.is_file():
        return set()
    fingerprints: set[str] = set()
    for line in results_jsonl.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        entry = json.loads(line)
        fingerprint = entry.get("fingerprint")
        if fingerprint:
            fingerprints.add(fingerprint)
    return fingerprints


def append_result(results_jsonl: Path, entry: dict[str, Any]) -> None:
    """Append one JSON line to the shared results file, creating it if needed."""
    results_jsonl.parent.mkdir(parents=True, exist_ok=True)
    with results_jsonl.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(entry) + "\n")
        handle.flush()
        os.fsync(handle.fileno())


def wait_for_server(process: subprocess.Popen[str]) -> None:
    """Wait for a benchmark server to become healthy."""
    deadline = time.monotonic() + SERVER_TIMEOUT
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError(f"llama-server exited with status {process.returncode}")
        try:
            with urllib.request.urlopen(f"{SERVER_URL}/health", timeout=2) as response:
                if json.loads(response.read()).get("status") == "ok":
                    return
        except OSError:
            pass
        time.sleep(1)
    raise TimeoutError("llama-server did not become healthy")


def stop_server(process: subprocess.Popen[str]) -> None:
    """Stop a benchmark server, escalating only if it does not exit."""
    if process.poll() is not None:
        return
    process.send_signal(signal.SIGTERM)
    try:
        process.wait(timeout=30)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=10)


def run_config(
    speed_bench: Path,
    config_name: str,
    server_args: list[str],
    output_dir: Path,
    categories: str,
    output_tokens: int,
    samples_per_category: int,
    concurrency: int,
    fingerprint: str,
) -> dict[str, Any]:
    """Start Ornith with one config through llama-server and run speed_bench.py."""
    command = [LLAMA_CPP_SERVER, *server_args]
    result_path = output_dir / f"{config_name}.json"
    log_path = output_dir / f"{config_name}.server.log"
    print(f"[{config_name}] {' '.join(command)}", flush=True)

    started = time.monotonic()
    with log_path.open("w", encoding="utf-8") as log_file:
        process = subprocess.Popen(
            command, stdout=log_file, stderr=subprocess.STDOUT, text=True, env=SERVER_ENV
        )
        try:
            wait_for_server(process)
            bench_command = [
                "uv",
                "run",
                "--no-project",
                "--with",
                "datasets",
                "--with",
                "requests",
                "--with",
                "tqdm",
                "python",
                str(speed_bench),
                "--url",
                SERVER_URL,
                "--bench",
                "qualitative",
                "--category",
                categories,
                "--osl",
                str(output_tokens),
                "--limit",
                str(samples_per_category),
                "--concurrency",
                str(concurrency),
                "--timeout",
                str(BENCH_TIMEOUT),
                "--output",
                str(result_path),
            ]
            subprocess.run(bench_command, check=True)
        finally:
            stop_server(process)
    elapsed = time.monotonic() - started

    payload = json.loads(result_path.read_text(encoding="utf-8"))
    overall = next(row for row in payload["summary"] if row["category"] == "overall")
    print(
        f"[{config_name}] decode={overall['avg_pred_t_s']:.2f} tok/s "
        f"latency={overall['avg_latency']:.2f}s accept={overall.get('accept_rate', 'N/A')} "
        f"wall={elapsed:.0f}s",
        flush=True,
    )

    jsonl_entry: dict[str, Any] = {
        "timestamp": time.strftime("%Y%m%d-%H%M%S"),
        "fingerprint": fingerprint,
        "model_id": MODEL_ID,
        "model_path": str(MODEL_PATH),
        "benchmark": "speed-bench",
        "config": config_name,
        "server_args": server_args,
        "params": {
            "categories": categories,
            "output_tokens": output_tokens,
            "samples_per_category": samples_per_category,
            "concurrency": concurrency,
        },
        "results": {
            "decode_tok_s": round(overall["avg_pred_t_s"], 3),
            "prompt_tok_s": round(overall["avg_prompt_t_s"], 3),
            "avg_latency_s": round(overall["avg_latency"], 3),
            "accept_rate": overall.get("accept_rate"),
            "wall_elapsed_sec": round(elapsed, 1),
        },
    }
    append_result(RESULTS_JSONL, jsonl_entry)

    return jsonl_entry


def start_detached_worker(args: argparse.Namespace) -> int:
    """Move work out of hermes-gateway's cgroup before stopping that gateway."""
    unit = f"hermes-ornith-sweep-{int(time.time())}"
    command = [
        "systemd-run",
        "--user",
        f"--unit={unit}",
        "--collect",
        "--property=Type=exec",
        sys.executable,
        str(Path(__file__).resolve()),
        "--worker",
        "--speed-bench",
        str(args.speed_bench),
        "--categories",
        args.categories,
        "--output-tokens",
        str(args.output_tokens),
        "--samples-per-category",
        str(args.samples_per_category),
        "--concurrency",
        str(args.concurrency),
        "--restore-model",
        args.restore_model,
    ]
    completed = subprocess.run(command, check=True, capture_output=True, text=True)
    print(completed.stdout.strip())
    print(f"Follow with: journalctl --user -fu {unit}")
    return 0


def run_worker(args: argparse.Namespace) -> int:
    """Stop Hermes, sweep configs, then restore the backend and Hermes."""
    if not MODEL_PATH.is_file():
        raise FileNotFoundError(MODEL_PATH)

    timestamp = time.strftime("%Y%m%d-%H%M%S")
    output_dir = DEFAULT_ARTIFACT_ROOT / f"{timestamp}-ornith-sweep"
    output_dir.mkdir(parents=True, exist_ok=False)
    summary: dict[str, Any] = {"timestamp": timestamp, "model_id": MODEL_ID, "configs": []}
    gateway_was_active = (
        subprocess.run(
            ["systemctl", "--user", "is-active", "--quiet", "hermes-gateway"], check=False
        ).returncode
        == 0
    )

    already_tested = load_tested_fingerprints(RESULTS_JSONL)
    pending: list[tuple[str, list[str], str]] = []
    for config_name, extra_args in SWEEP_CONFIGS:
        server_args = BASE_ARGS + extra_args
        fingerprint = config_fingerprint(
            MODEL_ID,
            MODEL_PATH,
            server_args,
            args.categories,
            args.output_tokens,
            args.samples_per_category,
            args.concurrency,
        )
        if fingerprint in already_tested:
            print(
                f"[{config_name}] skip: already benchmarked (fingerprint {fingerprint})",
                flush=True,
            )
            continue
        pending.append((config_name, server_args, fingerprint))

    benchmark_error: BaseException | None = None
    restore_error: BaseException | None = None
    try:
        if pending:
            if gateway_was_active:
                subprocess.run(["systemctl", "--user", "stop", "hermes-gateway"], check=True)
            unload_backend()
            for config_name, server_args, fingerprint in pending:
                summary["configs"].append(
                    run_config(
                        args.speed_bench,
                        config_name,
                        server_args,
                        output_dir,
                        args.categories,
                        args.output_tokens,
                        args.samples_per_category,
                        args.concurrency,
                        fingerprint,
                    )
                )
        else:
            print(
                "Nothing to benchmark — every config is already in results.jsonl", flush=True
            )
    except BaseException as exc:  # Restore the backend even on signals and interrupts.
        benchmark_error = exc

    if pending:
        try:
            unload_backend()
            restore_backend(args.restore_model)
            if gateway_was_active:
                subprocess.run(["systemctl", "--user", "start", "hermes-gateway"], check=True)
        except BaseException as exc:
            restore_error = exc

    if benchmark_error is not None:
        summary["benchmark_error"] = repr(benchmark_error)
    if restore_error is not None:
        summary["restore_error"] = repr(restore_error)

    summary_path = output_dir / "summary.json"
    summary_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")

    if benchmark_error is not None:
        if restore_error is not None:
            benchmark_error.add_note(f"backend restoration also failed: {restore_error!r}")
        raise benchmark_error
    if restore_error is not None:
        raise restore_error

    print(f"results: {summary_path}")
    return 0


def main() -> int:
    """Parse arguments and launch or execute the isolated worker."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--worker", action="store_true")
    parser.add_argument("--speed-bench", type=Path, default=DEFAULT_SPEED_BENCH)
    parser.add_argument("--categories", default=DEFAULT_CATEGORIES)
    parser.add_argument("--output-tokens", type=int, default=DEFAULT_OUTPUT_TOKENS)
    parser.add_argument("--samples-per-category", type=int, default=DEFAULT_SAMPLES_PER_CATEGORY)
    parser.add_argument("--concurrency", type=int, default=DEFAULT_CONCURRENCY)
    parser.add_argument("--restore-model", default=DEFAULT_RESTORE_MODEL)
    args = parser.parse_args()

    if not args.speed_bench.is_file():
        parser.error(f"speed_bench.py not found: {args.speed_bench}")
    return run_worker(args) if args.worker else start_detached_worker(args)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.SubprocessError, urllib.error.URLError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc
