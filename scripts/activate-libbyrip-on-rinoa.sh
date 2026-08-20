#!/usr/bin/env bash
# Restore staged LibbyRip state and activate the Rinoa NixOS configuration.
set -euo pipefail

readonly expected_host="rinoa"
readonly repo_dir="${DOTFILES_DIR:-$HOME/git/dotfiles}"
readonly staging_dir="${RINOA_STAGING_DIR:-/tmp/libbyrip-converter-data}"
readonly data_dir="/var/lib/docker-containers/libbyrip-converter/data"

if [[ "${1:-}" != "--yes" ]]; then
  echo "Usage: $0 --yes" >&2
  echo "Restores staged LibbyRip state and switches the Rinoa configuration." >&2
  exit 2
fi

if [[ "$(hostname --short)" != "${expected_host}" ]]; then
  echo "Run this script on ${expected_host}, not $(hostname --short)." >&2
  exit 1
fi

if [[ ! -d "${staging_dir}" ]]; then
  echo "Staged LibbyRip state is missing from ${staging_dir}." >&2
  exit 1
fi

if [[ ! -f "${repo_dir}/flake.nix" ]]; then
  echo "Dotfiles checkout is missing from ${repo_dir}." >&2
  exit 1
fi

echo "Restoring LibbyRip state..."
sudo install -d -m 0755 "${data_dir}"
sudo rsync -aHAX "${staging_dir}/" "${data_dir}/"

echo "Switching Rinoa to the converter configuration..."
sudo nixos-rebuild switch --flake "${repo_dir}#rinoa"

systemctl is-active --quiet docker-container-libbyrip-converter
[[ "$(docker inspect --format '{{.State.Health.Status}}' libbyrip-converter)" == "healthy" ]]
curl --fail --silent --show-error http://192.168.1.110:3002/health >/dev/null
curl --fail --silent --show-error https://converter.local.solivan.dev/ >/dev/null

echo "LibbyRip is healthy on Rinoa. Keep ${staging_dir} until you are satisfied with the migration."
