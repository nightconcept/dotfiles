#!/usr/bin/env python3
"""Quick A/B benchmark for llama-server token throughput.

Usage:
    python3 bench-llama.py          # label: unlabeled
    python3 bench-llama.py A        # before MTP
    python3 bench-llama.py B        # after MTP
"""

import json
import sys
import time
import urllib.request

URL = "http://localhost:8080/completion"
RUNS = 5
N_PREDICT = 200
PROMPT = (
    "Write a detailed technical explanation of how transformers work, "
    "covering attention mechanisms, positional encoding, and training."
)


def run_once() -> dict:
    payload = json.dumps({"prompt": PROMPT, "n_predict": N_PREDICT}).encode()
    req = urllib.request.Request(URL, data=payload, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as resp:
        return json.loads(resp.read())["timings"]


def main():
    label = sys.argv[1] if len(sys.argv) > 1 else "run"

    print(f"\n=== llama-server benchmark [{label}] ===")
    print(f"Prompt tokens: ~{len(PROMPT.split())*1.3:.0f} | Max new tokens: {N_PREDICT} | Runs: {RUNS}\n")

    pp_results, tg_results = [], []

    for i in range(1, RUNS + 1):
        print(f"Run {i}/{RUNS}...", end=" ", flush=True)
        t = run_once()
        pp = t["prompt_per_second"]
        tg = t["predicted_per_second"]
        pp_results.append(pp)
        tg_results.append(tg)
        print(f"pp={pp:6.1f} tok/s  tg={tg:6.1f} tok/s")
        if i < RUNS:
            time.sleep(1)

    # Drop best and worst tg to reduce variance
    if RUNS >= 3:
        tg_trimmed = sorted(tg_results)[1:-1]
        pp_trimmed = sorted(pp_results)[1:-1]
    else:
        tg_trimmed, pp_trimmed = tg_results, pp_results

    avg_pp = sum(pp_trimmed) / len(pp_trimmed)
    avg_tg = sum(tg_trimmed) / len(tg_trimmed)

    print(f"\n--- [{label}] averages (trimmed) ---")
    print(f"  Prompt processing (pp): {avg_pp:6.1f} tok/s")
    print(f"  Token generation  (tg): {avg_tg:6.1f} tok/s")
    print()


if __name__ == "__main__":
    main()
