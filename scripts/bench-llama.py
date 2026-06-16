#!/usr/bin/env python3
"""A/B benchmark comparing llama-server throughput with and without MTP.

Stops the running llama-server service, runs each config in sequence,
then prints a comparison table and restores the service.

Usage:
    python3 bench-llama.py
    python3 bench-llama.py --no-restore   # skip restarting the service after
"""

import argparse
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

URL = "http://localhost:8080"
RUNS = 5
N_PREDICT = 200
LLAMA_BIN = "/opt/llama-cpp/llama-server"
MODEL_DIR = "/opt/llm-models"

PROMPT = (
    "Write a detailed technical explanation of how transformers work, "
    "covering attention mechanisms, positional encoding, and training."
)

CONFIGS = [
    {
        "label": "baseline (Q6_K, no MTP)",
        "model": f"{MODEL_DIR}/Qwen3.6-35B-A3B-UD-Q6_K.gguf",
        "extra_args": [],
    },
    {
        "label": "MTP (Q5_K_XL, n-max 3)",
        "model": f"{MODEL_DIR}/Qwen3.6-35B-A3B-MTP-UD-Q5_K_XL.gguf",
        "extra_args": ["--spec-type", "draft-mtp", "--spec-draft-n-max", "3"],
    },
]

COMMON_ARGS = [
    "-c", "131072",
    "-ngl", "all",
    "-fa", "on",
    "-ctk", "q8_0",
    "-ctv", "q8_0",
    "--no-mmproj",
    "--jinja",
    "--host", "0.0.0.0",
    "--port", "8080",
]

SERVER_ENV = {
    **os.environ,
    "ROCM_PATH": "/opt/rocm",
    "LD_LIBRARY_PATH": "/opt/llama-cpp:/opt/rocm/lib:/opt/rocm/lib64",
}


def wait_for_server(timeout: int = 300) -> None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(f"{URL}/health", timeout=2) as r:
                if r.status == 200:
                    return
        except urllib.error.HTTPError as e:
            if e.code != 503:
                raise
        except Exception:
            pass
        time.sleep(2)
    raise TimeoutError("Server did not become ready within timeout")


def run_once() -> dict:
    payload = json.dumps({"prompt": PROMPT, "n_predict": N_PREDICT}).encode()
    req = urllib.request.Request(
        f"{URL}/completion",
        data=payload,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=180) as resp:
        return json.loads(resp.read())["timings"]


def benchmark(label: str) -> tuple[float, float]:
    print(f"\n  Running {RUNS} inference passes...")
    pp_results, tg_results = [], []
    for i in range(1, RUNS + 1):
        print(f"    [{i}/{RUNS}]", end=" ", flush=True)
        t = run_once()
        pp, tg = t["prompt_per_second"], t["predicted_per_second"]
        pp_results.append(pp)
        tg_results.append(tg)
        print(f"pp={pp:6.1f}  tg={tg:6.1f} tok/s")
        if i < RUNS:
            time.sleep(1)

    if RUNS >= 3:
        tg_trimmed = sorted(tg_results)[1:-1]
        pp_trimmed = sorted(pp_results)[1:-1]
    else:
        tg_trimmed, pp_trimmed = tg_results, pp_results

    avg_pp = sum(pp_trimmed) / len(pp_trimmed)
    avg_tg = sum(tg_trimmed) / len(tg_trimmed)
    print(f"  avg pp={avg_pp:.1f}  avg tg={avg_tg:.1f} tok/s (trimmed)")
    return avg_pp, avg_tg


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--no-restore",
        action="store_true",
        help="Don't restart llama-server.service after benchmarking",
    )
    args = parser.parse_args()

    print("Stopping llama-server.service...")
    subprocess.run(["sudo", "systemctl", "stop", "llama-server"], check=True)

    results: list[tuple[str, float, float]] = []
    proc: subprocess.Popen | None = None

    try:
        for cfg in CONFIGS:
            if proc is not None:
                proc.terminate()
                try:
                    proc.wait(timeout=30)
                except subprocess.TimeoutExpired:
                    proc.kill()
                proc = None
                time.sleep(3)

            cmd = [LLAMA_BIN, "-m", cfg["model"]] + COMMON_ARGS + cfg["extra_args"]
            print(f"\n--- {cfg['label']} ---")
            print(f"  Starting server...")
            proc = subprocess.Popen(cmd, env=SERVER_ENV, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

            print("  Waiting for readiness...", end=" ", flush=True)
            wait_for_server()
            print("ready.")

            avg_pp, avg_tg = benchmark(cfg["label"])
            results.append((cfg["label"], avg_pp, avg_tg))

    except KeyboardInterrupt:
        print("\nInterrupted.")
        sys.exit(1)
    finally:
        if proc is not None:
            proc.terminate()
            try:
                proc.wait(timeout=30)
            except subprocess.TimeoutExpired:
                proc.kill()

        if not args.no_restore:
            print("\nRestarting llama-server.service...")
            subprocess.run(["sudo", "systemctl", "start", "llama-server"], check=False)

    if not results:
        return

    w = 30
    print(f"\n{'=' * 58}")
    print(f"{'Configuration':<{w}} {'PP (tok/s)':>12} {'TG (tok/s)':>12}")
    print(f"{'-' * 58}")
    for label, pp, tg in results:
        print(f"{label:<{w}} {pp:>12.1f} {tg:>12.1f}")

    if len(results) == 2:
        _, pp_a, tg_a = results[0]
        _, pp_b, tg_b = results[1]
        print(f"{'-' * 58}")
        print(f"{'delta':<{w}} {pp_b - pp_a:>+12.1f} {tg_b - tg_a:>+12.1f}")
        print(f"{'speedup':<{w}} {pp_b / pp_a:>11.2f}x {tg_b / tg_a:>11.2f}x")
    print(f"{'=' * 58}")


if __name__ == "__main__":
    main()
