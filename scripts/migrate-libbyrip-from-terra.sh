#!/usr/bin/env bash
# Stop LibbyRip on Terra and copy its mutable state to Rinoa for cutover.
set -euo pipefail

readonly expected_host="terra"
readonly rinoa_target="${RINOA_TARGET:-danny@rinoa}"
readonly source_dir="/opt/libbyrip-converter"
readonly staging_dir="${RINOA_STAGING_DIR:-/tmp/libbyrip-converter-data}"

if [[ "${1:-}" != "--yes" ]]; then
  echo "Usage: $0 --yes" >&2
  echo "Stops LibbyRip on Terra and copies its state to ${rinoa_target}:${staging_dir}." >&2
  exit 2
fi

if [[ "$(hostname --short)" != "${expected_host}" ]]; then
  echo "Run this script on ${expected_host}, not $(hostname --short)." >&2
  exit 1
fi

if [[ ! -f "${source_dir}/.env" || ! -f "${source_dir}/docker-compose.yml" ]]; then
  echo "LibbyRip deployment files are missing from ${source_dir}." >&2
  exit 1
fi

echo "Stopping LibbyRip on Terra..."
sudo docker compose \
  --env-file "${source_dir}/.env" \
  -f "${source_dir}/docker-compose.yml" \
  down

echo "Copying LibbyRip state to Rinoa staging..."
rsync -aHAX --numeric-ids \
  "${source_dir}/data/" \
  "${rinoa_target}:${staging_dir}/"

echo "Terra is stopped and state is staged on Rinoa."
echo "Next: run scripts/activate-libbyrip-on-rinoa.sh --yes on Rinoa."
