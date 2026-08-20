#!/usr/bin/env bash
# Build locally, copy the closure, and switch the Rinoa NixOS configuration over SSH.
set -euo pipefail

readonly repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly target_host="${RINOA_TARGET:-danny@rinoa}"

if [[ "${1:-}" != "--yes" ]]; then
  echo "Usage: $0 --yes" >&2
  echo "Builds .#rinoa locally and switches ${target_host} through SSH." >&2
  exit 2
fi

exec nixos-rebuild switch \
  --flake "${repo_dir}#rinoa" \
  --target-host "${target_host}" \
  --use-remote-sudo
