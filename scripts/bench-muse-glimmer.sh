#!/usr/bin/env bash
# Swap in the Muse Glimmer 30B config on terra's llama-swap, run the
# benchmark suite against it and the qwen3-35b-mtp / qwen3-27b-dense
# baselines, then restore the original config.
#
# Requires sudo (writes /etc/llama-swap/config.yaml, restarts the systemd
# unit). Run this script directly so the sudo prompt appears once up front.
set -euo pipefail

NEW_CONFIG="/tmp/llama-swap-new-config.yaml"
LIVE_CONFIG="/etc/llama-swap/config.yaml"
BACKUP_CONFIG="/etc/llama-swap/config.yaml.bak.$(date +%Y%m%d%H%M%S)"
RESULTS_DIR="/tmp/bench-llama-swap-results"
BENCH_SCRIPT="$(dirname "$0")/bench-llama-swap.py"

if [[ ! -f "$NEW_CONFIG" ]]; then
  echo "Missing $NEW_CONFIG (prepared config with muse-glimmer-30b entry)" >&2
  exit 1
fi

restore_config() {
  echo "Restoring original llama-swap config..."
  sudo cp "$BACKUP_CONFIG" "$LIVE_CONFIG"
  sudo systemctl restart llama-swap
}

echo "==> Backing up current config to $BACKUP_CONFIG"
sudo cp "$LIVE_CONFIG" "$BACKUP_CONFIG"

echo "==> Installing new config with muse-glimmer-30b"
sudo cp "$NEW_CONFIG" "$LIVE_CONFIG"

echo "==> Restarting llama-swap"
sudo systemctl restart llama-swap

trap restore_config EXIT

echo "==> Waiting for llama-swap to come up"
for i in $(seq 1 30); do
  if curl -fs http://127.0.0.1:8080/v1/models >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

mkdir -p "$RESULTS_DIR"

echo "==> Benchmarking muse-glimmer-30b (text, DFlash spec decoding)"
python3 "$BENCH_SCRIPT" \
  --models muse-glimmer-30b \
  --runs 5 \
  --max-tokens 200 \
  --warmup-max-tokens 16

echo "==> Benchmarking qwen3-35b-mtp (baseline, same params)"
python3 "$BENCH_SCRIPT" \
  --models qwen3-35b-mtp \
  --runs 5 \
  --max-tokens 200 \
  --warmup-max-tokens 16

echo "==> Benchmarking qwen3-27b-dense (baseline, same params)"
python3 "$BENCH_SCRIPT" \
  --models qwen3-27b-dense \
  --runs 5 \
  --max-tokens 200 \
  --warmup-max-tokens 16

echo "==> Benchmarking muse-glimmer-30b (context stress, max-tokens 1000)"
python3 "$BENCH_SCRIPT" \
  --models muse-glimmer-30b \
  --runs 3 \
  --max-tokens 1000 \
  --warmup-max-tokens 16

echo "==> Results written under $RESULTS_DIR"
echo "==> Restoring config on exit"
