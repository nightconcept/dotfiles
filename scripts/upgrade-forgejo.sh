#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

HOST_NAME="${1:-$(hostname -s)}"
CONTAINER_DIR="/var/lib/docker-containers/forgejo"
REPO_COMPOSE="${REPO_ROOT}/modules/nixos/services/docker/containers/forgejo/docker-compose.yml"
DEPLOYED_COMPOSE="${CONTAINER_DIR}/docker-compose.yml"
SERVICE_NAME="docker-container-forgejo.service"

need_rebuild=false

if [[ ! -f "${DEPLOYED_COMPOSE}" ]]; then
  echo "Deployed Forgejo compose file is missing; rebuild required."
  need_rebuild=true
elif ! cmp -s "${REPO_COMPOSE}" "${DEPLOYED_COMPOSE}"; then
  echo "Repo Forgejo compose file differs from the deployed version; rebuild required."
  need_rebuild=true
fi

if ! systemctl list-unit-files "${SERVICE_NAME}" >/dev/null 2>&1; then
  echo "Forgejo systemd unit is not installed; rebuild required."
  need_rebuild=true
fi

if [[ "${need_rebuild}" == "true" ]]; then
  echo "Running nixos-rebuild for host ${HOST_NAME}..."
  sudo nixos-rebuild switch --flake "${REPO_ROOT}#${HOST_NAME}"
else
  echo "Deployed Forgejo config already matches the repo; skipping rebuild."
fi

echo "Flushing Forgejo queues before upgrade..."
if docker ps --format '{{.Names}}' | grep -qx 'forgejo'; then
  docker exec forgejo forgejo manager flush-queues || true
fi

echo "Pulling Forgejo image..."
docker compose -f "${DEPLOYED_COMPOSE}" --project-directory "${CONTAINER_DIR}" pull forgejo

echo "Recreating Forgejo container..."
docker compose -f "${DEPLOYED_COMPOSE}" --project-directory "${CONTAINER_DIR}" up -d forgejo

echo "Upgrade complete. Verify the instance and run 'docker exec forgejo forgejo doctor check --all' if desired."
