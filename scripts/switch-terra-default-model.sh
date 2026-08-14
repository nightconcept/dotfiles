#!/usr/bin/env bash
# Promote muse-glimmer-30b to terra's default served model, permanently:
#   1. Runs `just terra` — rebuilds/installs llama.cpp at the pinned commit
#      (689e227db, includes Muse Glimmer support) into /opt/llama-cpp and
#      redeploys /etc/llama-swap/config.yaml from model_catalog.py, which
#      now includes the muse-glimmer-30b entry.
#   2. Points Hermes's default model + custom_providers entry at
#      muse-glimmer-30b (context_length was already 131072 / 128k).
#   3. Restarts the hermes-gateway user service to pick up the new config.
#
# Requires sudo (pyinfra applies system changes) and will briefly interrupt
# any in-flight Hermes conversations when the gateway restarts. Run this
# script directly so the sudo prompt appears once up front.
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HERMES_CONFIG="$HOME/.hermes/config.yaml"

echo "==> Deploying terra (llama.cpp rebuild + llama-swap config)"
(cd "$DOTFILES_DIR" && just terra)

echo "==> Verifying llama-swap serves muse-glimmer-30b"
curl -fs http://127.0.0.1:8080/v1/models | grep -q muse-glimmer-30b \
  || { echo "muse-glimmer-30b not found in llama-swap /v1/models" >&2; exit 1; }

echo "==> Backing up Hermes config"
cp "$HERMES_CONFIG" "$HERMES_CONFIG.bak.$(date +%Y%m%d%H%M%S)"

echo "==> Pointing Hermes at muse-glimmer-30b"
sed -i \
  -e '0,/^  default: qwen3-35b-mtp$/{s/^  default: qwen3-35b-mtp$/  default: muse-glimmer-30b/}' \
  -e 's/^  model: qwen3-35b-mtp$/  model: muse-glimmer-30b/' \
  "$HERMES_CONFIG"

grep -n "default: muse-glimmer-30b\|model: muse-glimmer-30b" "$HERMES_CONFIG"

echo "==> Restarting hermes-gateway"
systemctl --user restart hermes-gateway.service

echo "==> Done. Hermes's default model is now muse-glimmer-30b (131072 / 128k context)."
