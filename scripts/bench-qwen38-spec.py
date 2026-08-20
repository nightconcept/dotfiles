#!/usr/bin/env python3
"""Benchmark Qwen3.8 server-side generation options and restore Hermes."""

from __future__ import annotations

import argparse
import json
import os
import signal
import subprocess
import sys
import time
import urllib.request
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT))

from modules.linux.programs.model_catalog import (  # noqa: E402
    DEFAULT_MODEL_ID,
    MODEL_CATALOG,
    MODEL_DIR,
)

LLAMA_SWAP_URL = "http://127.0.0.1:8080"
LLAMA_SERVER = Path("/opt/llama-cpp/llama-server")
SPEED_BENCH = Path("/home/danny/git/llama.cpp/tools/server/bench/speed-bench/speed_bench.py")
ARTIFACT_ROOT = Path.home() / ".hermes" / "benchmarks"
MODEL_ID = "qwen3.8-27b"
SERVER_URL = "http://127.0.0.1:18080"
SERVER_TIMEOUT = 900
BENCH_CATEGORIES = "coding,reasoning,summarization,writing"

CATALOG_BY_ID = {model["id"]: model for model in MODEL_CATALOG}
MODEL_PATH = Path(MODEL_DIR) / CATALOG_BY_ID[MODEL_ID]["files"][0]
BASE_SERVER_ARGS = [
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
    "18080",
]


def request_json(url: str, *, payload: dict[str, Any] | None = None, timeout: int = 30) -> Any:
    """Send one JSON HTTP request."""
    data = json.dumps(payload).encode() if payload is not None else None
    request = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST" if payload is not None else "GET",
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        body = response.read()
    return json.loads(body) if body else None


def unload_backend() -> None:
    """Unload llama-swap's active child server."""
    request_json(f"{LLAMA_SWAP_URL}/api/models/unload", payload={})
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        if not request_json(f"{LLAMA_SWAP_URL}/running").get("running", []):
            return
        time.sleep(0.25)
    raise RuntimeError("llama-swap did not unload its backend")


def restore_backend() -> None:
    """Restore the configured production model through llama-swap."""
    request_json(
        f"{LLAMA_SWAP_URL}/v1/chat/completions",
        payload={
            "model": DEFAULT_MODEL_ID,
            "messages": [{"role": "user", "content": "Reply with exactly: ready"}],
            "max_tokens": 8,
            "temperature": 0,
            "chat_template_kwargs": {"enable_thinking": False},
        },
        timeout=SERVER_TIMEOUT,
    )


def wait_for_server(process: subprocess.Popen[str]) -> None:
    """Wait for a benchmark server to become healthy."""
    deadline = time.monotonic() + SERVER_TIMEOUT
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError(f"llama-server exited with status {process.returncode}")
        try:
            if request_json(f"{SERVER_URL}/health", timeout=2).get("status") == "ok":
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


def overall_result(path: Path) -> dict[str, Any]:
    """Return the overall SPEED-Bench summary row."""
    payload = json.loads(path.read_text(encoding="utf-8"))
    return next(row for row in payload["summary"] if row["category"] == "overall")


def run_config(
    name: str, extra_server_args: list[str], output_dir: Path, args: argparse.Namespace
) -> dict[str, Any]:
    """Start one server configuration and run SPEED-Bench against it."""
    result_path = output_dir / f"{name}.json"
    log_path = output_dir / f"{name}.server.log"
    command = [str(LLAMA_SERVER), *BASE_SERVER_ARGS, *extra_server_args]
    environment = os.environ.copy()
    environment.update(
        {
            "ROCM_PATH": "/opt/rocm",
            "LD_LIBRARY_PATH": "/opt/llama-cpp:/opt/rocm/lib:/opt/rocm/lib64",
        }
    )
    print(f"[{name}] starting {' '.join(command)}", flush=True)
    started = time.monotonic()
    with log_path.open("w", encoding="utf-8") as log_file:
        process = subprocess.Popen(
            command,
            stdout=log_file,
            stderr=subprocess.STDOUT,
            text=True,
            env=environment,
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
                str(SPEED_BENCH),
                "--url",
                SERVER_URL,
                "--bench",
                "qualitative",
                "--category",
                BENCH_CATEGORIES,
                "--osl",
                str(args.output_tokens),
                "--limit",
                str(args.samples_per_category),
                "--concurrency",
                "1",
                "--timeout",
                "900",
                "--output",
                str(result_path),
            ]
            subprocess.run(bench_command, check=True)
        finally:
            stop_server(process)

    result = overall_result(result_path)
    result.update(
        {
            "name": name,
            "server_args": extra_server_args,
            "wall_elapsed_s": time.monotonic() - started,
        }
    )
    print(
        f"[{name}] decode={result['avg_pred_t_s']:.3f} t/s "
        f"latency={result['avg_latency']:.3f}s "
        f"acceptance={result['accept_rate']}",
        flush=True,
    )
    return result


def write_summary(output_dir: Path, results: list[dict[str, Any]]) -> Path:
    """Persist comparisons against the plain server baseline."""
    baseline = results[0]
    for result in results:
        result["decode_speedup_vs_baseline"] = result["avg_pred_t_s"] / baseline["avg_pred_t_s"]
        result["latency_speedup_vs_baseline"] = baseline["avg_latency"] / result["avg_latency"]
    summary_path = output_dir / "summary.json"
    summary_path.write_text(
        json.dumps(
            {
                "model": MODEL_ID,
                "model_path": str(MODEL_PATH),
                "categories": BENCH_CATEGORIES,
                "results": results,
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    return summary_path


def run_worker(args: argparse.Namespace) -> int:
    """Run the matrix with Hermes stopped, then restore production."""
    timestamp = time.strftime("%Y%m%d-%H%M%S")
    output_dir = ARTIFACT_ROOT / f"{timestamp}-qwen38-speed"
    output_dir.mkdir(parents=True)
    gateway_was_active = (
        subprocess.run(
            ["systemctl", "--user", "is-active", "--quiet", "hermes-gateway"],
            check=False,
        ).returncode
        == 0
    )
    error: BaseException | None = None
    results: list[dict[str, Any]] = []
    try:
        if gateway_was_active:
            subprocess.run(["systemctl", "--user", "stop", "hermes-gateway"], check=True)
        unload_backend()

        results.append(run_config("baseline", [], output_dir, args))
        for width in (2, 3, 4):
            results.append(
                run_config(
                    f"mtp-{width}",
                    ["--spec-type", "draft-mtp", "--spec-draft-n-max", str(width)],
                    output_dir,
                    args,
                )
            )

        mtp_winner = max(results[1:4], key=lambda item: item["avg_pred_t_s"])
        winner_args = list(mtp_winner["server_args"])
        results.append(
            run_config(f"{mtp_winner['name']}-np1", [*winner_args, "-np", "1"], output_dir, args)
        )
        results.append(
            run_config(
                f"{mtp_winner['name']}-np1-backend-sampling",
                [*winner_args, "-np", "1", "--backend-sampling"],
                output_dir,
                args,
            )
        )
        combined_args = [
            "draft-mtp,ngram-mod" if value == "draft-mtp" else value for value in winner_args
        ]
        results.append(
            run_config(
                f"{mtp_winner['name']}-np1-ngram-mod",
                [*combined_args, "-np", "1"],
                output_dir,
                args,
            )
        )
        summary_path = write_summary(output_dir, results)
        print(f"results: {summary_path}", flush=True)
    except BaseException as exc:
        error = exc
    finally:
        try:
            unload_backend()
            restore_backend()
            if gateway_was_active:
                subprocess.run(["systemctl", "--user", "start", "hermes-gateway"], check=True)
        except BaseException as restore_exc:
            if error is None:
                error = restore_exc
            else:
                error.add_note(f"restoration also failed: {restore_exc!r}")
    if error is not None:
        raise error
    return 0


def start_detached_worker(args: argparse.Namespace) -> int:
    """Run outside hermes-gateway's cgroup so the worker can stop the gateway."""
    unit = f"hermes-qwen38-speed-{int(time.time())}"
    command = [
        "systemd-run",
        "--user",
        f"--unit={unit}",
        "--collect",
        "--property=Type=exec",
        sys.executable,
        str(Path(__file__).resolve()),
        "--worker",
        "--samples-per-category",
        str(args.samples_per_category),
        "--output-tokens",
        str(args.output_tokens),
    ]
    completed = subprocess.run(command, check=True, capture_output=True, text=True)
    print(completed.stdout.strip())
    print(f"Follow with: journalctl --user -fu {unit}")
    return 0


def main() -> int:
    """Parse arguments and launch the safe detached worker."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--worker", action="store_true")
    parser.add_argument("--samples-per-category", type=int, default=2)
    parser.add_argument("--output-tokens", type=int, default=256)
    args = parser.parse_args()
    for required_path in (LLAMA_SERVER, SPEED_BENCH, MODEL_PATH):
        if not required_path.is_file():
            parser.error(f"required file is missing: {required_path}")
    return run_worker(args) if args.worker else start_detached_worker(args)


if __name__ == "__main__":
    raise SystemExit(main())
