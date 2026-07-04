#!/usr/bin/env bash
set -euo pipefail

HOST_EXPECTED="terra"
LLAMA_SERVICE="llama-server"
LLAMA_URL="http://127.0.0.1:8080/health"
LLAMA_TIMEOUT_SECS="${LLAMA_TIMEOUT_SECS:-900}"
HERMES_SERVICE="hermes-gateway"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
HERMES_STATE_FILE="$HERMES_HOME/gateway_state.json"
HERMES_TIMEOUT_SECS="${HERMES_TIMEOUT_SECS:-90}"

log() {
  printf '%s\n' "$*"
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

host_name() {
  hostnamectl --static 2>/dev/null || hostname -s
}

run_systemctl() {
  if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    systemctl "$@"
  else
    sudo systemctl "$@"
  fi
}

llama_service_active() {
  systemctl is-active --quiet "$LLAMA_SERVICE"
}

llama_health_code() {
  curl -sS -o /dev/null -w '%{http_code}' "$LLAMA_URL" 2>/dev/null || true
}

llama_healthy() {
  [ "$(llama_health_code)" = "200" ]
}

wait_for_llama() {
  local deadline now code
  deadline=$(( $(date +%s) + LLAMA_TIMEOUT_SECS ))

  while :; do
    if llama_healthy; then
      return 0
    fi

    if ! llama_service_active; then
      return 1
    fi

    now="$(date +%s)"
    if [ "$now" -ge "$deadline" ]; then
      code="$(llama_health_code)"
      log "llama.cpp did not become healthy within ${LLAMA_TIMEOUT_SECS}s (last HTTP status: ${code:-none})"
      run_systemctl status "$LLAMA_SERVICE" --no-pager || true
      return 1
    fi

    sleep 5
  done
}

hermes_main_pid() {
  systemctl --user show -p MainPID --value "$HERMES_SERVICE" 2>/dev/null | tr -d '[:space:]'
}

hermes_state_running_for_main_pid() {
  local main_pid
  main_pid="$(hermes_main_pid)"
  [ -n "$main_pid" ] || return 1
  [ "$main_pid" != "0" ] || return 1
  [ -f "$HERMES_STATE_FILE" ] || return 1

  python3 - "$HERMES_STATE_FILE" "$main_pid" <<'PY'
import json
import sys

path = sys.argv[1]
main_pid = int(sys.argv[2])

try:
    with open(path, "r", encoding="utf-8") as handle:
        data = json.load(handle)
except Exception:
    raise SystemExit(1)

try:
    state_pid = int(data.get("pid", 0) or 0)
except (TypeError, ValueError):
    raise SystemExit(1)

if state_pid != main_pid:
    raise SystemExit(1)

if data.get("gateway_state") != "running":
    raise SystemExit(1)
PY
}

hermes_service_active() {
  systemctl --user is-active --quiet "$HERMES_SERVICE"
}

hermes_healthy() {
  llama_healthy && hermes_service_active && hermes_state_running_for_main_pid
}

wait_for_hermes() {
  local deadline
  deadline=$(( $(date +%s) + HERMES_TIMEOUT_SECS ))

  while :; do
    if hermes_healthy; then
      return 0
    fi

    if ! hermes_service_active; then
      return 1
    fi

    if [ "$(date +%s)" -ge "$deadline" ]; then
      log "hermes-agent did not become healthy within ${HERMES_TIMEOUT_SECS}s"
      systemctl --user status "$HERMES_SERVICE" --no-pager || true
      return 1
    fi

    sleep 3
  done
}

ensure_llama() {
  if llama_healthy; then
    log "llama.cpp is already healthy on :8080"
    return 0
  fi

  if llama_service_active; then
    log "llama.cpp is running but not healthy yet; waiting for model load"
  else
    log "starting llama.cpp system service"
    run_systemctl start "$LLAMA_SERVICE"
  fi

  wait_for_llama || die "llama.cpp failed to become healthy"
  log "llama.cpp is healthy on :8080"
}

ensure_hermes() {
  if hermes_healthy; then
    log "hermes-agent is already healthy"
    return 0
  fi

  if hermes_service_active; then
    log "hermes-agent is running but not fully healthy; waiting"
  else
    log "starting hermes-agent user service"
    systemctl --user start "$HERMES_SERVICE"
  fi

  wait_for_hermes || die "hermes-agent failed to become healthy"
  log "hermes-agent is healthy"
}

main() {
  need_cmd curl
  need_cmd python3
  need_cmd systemctl

  if [ "$(host_name)" != "$HOST_EXPECTED" ]; then
    die "this script is intended for ${HOST_EXPECTED}"
  fi

  systemctl list-unit-files "$LLAMA_SERVICE.service" >/dev/null 2>&1 || die "missing ${LLAMA_SERVICE}.service"
  systemctl --user list-unit-files "$HERMES_SERVICE.service" >/dev/null 2>&1 || die "missing ${HERMES_SERVICE}.service"

  ensure_llama
  ensure_hermes

  log "local AI services are usable"
}

main "$@"
