#!/usr/bin/env bash
set -euo pipefail

MODEL_PATH="${MODEL_PATH:-/opt/llm-models/Qwen3.6-35B-A3B-MTP-UD-Q5_K_XL.gguf}"
LLAMA_BIN="${LLAMA_BIN:-/opt/llama-cpp/llama-server}"
PORT="${PORT:-8080}"
RUNS="${RUNS:-3}"
N_PREDICT="${N_PREDICT:-200}"
CONTEXT="${CONTEXT:-131072}"
READY_TIMEOUT="${READY_TIMEOUT:-900}"
ARTIFACT_ROOT="${ARTIFACT_ROOT:-/tmp/bench-llama-args-results}"
RESTORE_PID_FILE="/tmp/bench-llama-args.restore.pid"

CURRENT_ARGS=(
  -m "$MODEL_PATH"
  -c "$CONTEXT"
  -ngl all
  -fa on
  -ctk q8_0
  -ctv q8_0
  --no-mmproj
  --jinja
  --spec-type draft-mtp
  --spec-draft-n-max 3
  --host 127.0.0.1
  --port "$PORT"
)

CANDIDATE_ARGS=(
  -m "$MODEL_PATH"
  -c "$CONTEXT"
  -ngl all
  -fa on
  -ctk q8_0
  -ctv q8_0
  --no-mmproj
  --jinja
  --parallel 1
  --spec-type draft-mtp
  --spec-draft-n-max 2
  --spec-draft-p-min 0.75
  --host 127.0.0.1
  --port "$PORT"
)

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

json_get() {
  python3 - "$1" "$2" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
key = sys.argv[2]
value = payload
for part in key.split("."):
    value = value[part]
print(value)
PY
}

health_code() {
  curl -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/health" 2>/dev/null || true
}

wait_for_port_closed() {
  local deadline
  deadline=$(( $(date +%s) + 60 ))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    if ! ss -ltn "( sport = :${PORT} )" | tail -n +2 | grep -q .; then
      return 0
    fi
    sleep 1
  done
  return 1
}

wait_for_server() {
  local deadline code
  deadline=$(( $(date +%s) + READY_TIMEOUT ))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    code="$(health_code)"
    if [ "$code" = "200" ]; then
      return 0
    fi
    if [ -n "$code" ] && [ "$code" != "503" ] && [ "$code" != "000" ]; then
      die "unexpected health status on :${PORT}: ${code}"
    fi
    sleep 2
  done
  die "server on :${PORT} did not become ready within ${READY_TIMEOUT}s"
}

server_request() {
  local prompt="$1"
  local n_predict="$2"
  python3 - "$PORT" "$prompt" "$n_predict" <<'PY'
import json
import sys
import urllib.request

port = sys.argv[1]
prompt = sys.argv[2]
n_predict = int(sys.argv[3])
payload = json.dumps({
    "prompt": prompt,
    "n_predict": n_predict,
    "temperature": 0,
    "top_k": 1,
    "top_p": 1.0,
    "min_p": 0.0,
    "repeat_penalty": 1.0,
    "cache_prompt": False,
}).encode()
request = urllib.request.Request(
    f"http://127.0.0.1:{port}/completion",
    data=payload,
    headers={"Content-Type": "application/json"},
)
with urllib.request.urlopen(request, timeout=600) as response:
    print(response.read().decode())
PY
}

start_manual_server() {
  local pid_file="$1"
  shift
  "$LLAMA_BIN" "$@" >/tmp/bench-llama-args.server.log 2>&1 &
  local pid=$!
  printf '%s\n' "$pid" >"$pid_file"
  wait_for_server
}

stop_manual_server() {
  local pid_file="$1"
  [ -f "$pid_file" ] || return 0
  local pid
  pid="$(cat "$pid_file")"
  if kill -0 "$pid" >/dev/null 2>&1; then
    kill -TERM "$pid" >/dev/null 2>&1 || true
    wait "$pid" 2>/dev/null || true
  fi
  rm -f "$pid_file"
  wait_for_port_closed || true
}

try_systemctl_stop() {
  if systemctl stop llama-server >/dev/null 2>&1; then
    return 0
  fi
  if sudo -n systemctl stop llama-server >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

try_systemctl_start() {
  if systemctl start llama-server >/dev/null 2>&1; then
    return 0
  fi
  if sudo -n systemctl start llama-server >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

stop_live_service() {
  local pid
  pid="$(systemctl show -p MainPID --value llama-server 2>/dev/null | tr -d '[:space:]')"
  if try_systemctl_stop; then
    return 0
  fi
  if [ -n "$pid" ] && [ "$pid" != "0" ]; then
    kill -TERM "$pid" >/dev/null 2>&1 || true
    sleep 2
    wait_for_port_closed || true
    return 0
  fi
  return 1
}

benchmark_server() {
  local label="$1"
  local source="$2"
  local raw_file="$3"
  local prompt='You are debugging a production inference deployment. Explain, in technical depth, how speculative decoding with draft MTP heads interacts with KV cache precision, flash attention, batching, and long context limits on ROCm. Include concrete tradeoffs, failure modes, and what metrics you would watch when deciding whether to upgrade llama.cpp.'

  log
  log "[$label]"
  log "  source: $source on :$PORT"
  log "  warming up..."
  server_request "Reply with exactly: OK" 16 >/dev/null

  : >"$raw_file"
  local run prompt_tps gen_tps result
  for run in $(seq 1 "$RUNS"); do
    result="$(server_request "$prompt" "$N_PREDICT")"
    prompt_tps="$(json_get "$result" "timings.prompt_per_second")"
    gen_tps="$(json_get "$result" "timings.predicted_per_second")"
    printf '%s\t%s\n' "$prompt_tps" "$gen_tps" >>"$raw_file"
    log "  run ${run}/${RUNS}: prompt=$(printf '%6.1f' "$prompt_tps") tok/s  gen=$(printf '%6.1f' "$gen_tps") tok/s"
    if [ "$run" -lt "$RUNS" ]; then
      sleep 1
    fi
  done
}

summarize_results() {
  local current_raw="$1"
  local candidate_raw="$2"
  local artifact_dir="$3"
  python3 - "$current_raw" "$candidate_raw" "$artifact_dir" "$MODEL_PATH" "$CONTEXT" "$RUNS" "$N_PREDICT" <<'PY'
import json
import sys
from pathlib import Path

current_raw = Path(sys.argv[1])
candidate_raw = Path(sys.argv[2])
artifact_dir = Path(sys.argv[3])
model_path = sys.argv[4]
context = int(sys.argv[5])
runs = int(sys.argv[6])
n_predict = int(sys.argv[7])

def load_pairs(path: Path):
    pairs = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        prompt, gen = line.split("\t")
        pairs.append((float(prompt), float(gen)))
    return pairs

def avg(items):
    return sum(items) / len(items)

current = load_pairs(current_raw)
candidate = load_pairs(candidate_raw)

current_prompt = avg([x for x, _ in current])
current_gen = avg([y for _, y in current])
candidate_prompt = avg([x for x, _ in candidate])
candidate_gen = avg([y for _, y in candidate])

delta_prompt = candidate_prompt - current_prompt
delta_gen = candidate_gen - current_gen
delta_prompt_pct = (delta_prompt / current_prompt * 100.0) if current_prompt else 0.0
delta_gen_pct = (delta_gen / current_gen * 100.0) if current_gen else 0.0

summary = {
    "model": model_path,
    "context": context,
    "runs": runs,
    "n_predict": n_predict,
    "results": {
        "current_args": {
            "prompt_tps": current_prompt,
            "gen_tps": current_gen,
            "runs": current,
        },
        "candidate_args": {
            "prompt_tps": candidate_prompt,
            "gen_tps": candidate_gen,
            "runs": candidate,
        },
    },
    "delta": {
        "prompt_tps": delta_prompt,
        "prompt_pct": delta_prompt_pct,
        "gen_tps": delta_gen,
        "gen_pct": delta_gen_pct,
    },
}

(artifact_dir / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
(artifact_dir / "summary.tsv").write_text(
    "\n".join([
        "label\tprompt_tps\tgen_tps",
        f"current_args\t{current_prompt:.3f}\t{current_gen:.3f}",
        f"candidate_args\t{candidate_prompt:.3f}\t{candidate_gen:.3f}",
        f"delta\t{delta_prompt:.3f}\t{delta_gen:.3f}",
        f"delta_pct\t{delta_prompt_pct:.3f}\t{delta_gen_pct:.3f}",
    ]) + "\n",
    encoding="utf-8",
)

print()
print("Configuration")
print(f"  model:    {Path(model_path).name}")
print(f"  context:  {context}")
print(f"  runs:     {runs}")
print(f"  predict:  {n_predict}")

print()
print("Results")
print(f"  current    prompt={current_prompt:6.1f} tok/s  gen={current_gen:6.1f} tok/s")
print(f"  candidate  prompt={candidate_prompt:6.1f} tok/s  gen={candidate_gen:6.1f} tok/s")

print()
print("Delta (candidate - current)")
print(f"  prompt: {delta_prompt:+.1f} tok/s ({delta_prompt_pct:+.2f}%)")
print(f"  gen:    {delta_gen:+.1f} tok/s ({delta_gen_pct:+.2f}%)")

print()
print("Artifacts")
print(f"  summary: {artifact_dir / 'summary.tsv'}")
print(f"  raw current: {current_raw}")
print(f"  raw candidate: {candidate_raw}")
PY
}

restore_original_mode="none"
restore_was_live=0
current_pid_file="/tmp/bench-llama-args.current.pid"
candidate_pid_file="/tmp/bench-llama-args.candidate.pid"

cleanup() {
  stop_manual_server "$candidate_pid_file"
  stop_manual_server "$current_pid_file"
  if [ "$restore_was_live" -eq 1 ]; then
    if [ "$restore_original_mode" = "systemd" ]; then
      try_systemctl_start || true
    elif [ "$restore_original_mode" = "manual" ]; then
      if ! ss -ltn "( sport = :${PORT} )" | tail -n +2 | grep -q .; then
        "$LLAMA_BIN" "${CURRENT_ARGS[@]}" >/tmp/bench-llama-args.restore.log 2>&1 &
        printf '%s\n' "$!" >"$RESTORE_PID_FILE"
      fi
    fi
  fi
}

trap cleanup EXIT INT TERM

main() {
  need_cmd python3
  need_cmd curl
  need_cmd ss
  [ -x "$LLAMA_BIN" ] || die "missing llama-server binary: $LLAMA_BIN"
  [ -f "$MODEL_PATH" ] || die "missing model file: $MODEL_PATH"

  local timestamp artifact_dir
  timestamp="$(date +%Y%m%d-%H%M%S)"
  artifact_dir="${ARTIFACT_ROOT}/${timestamp}"
  mkdir -p "$artifact_dir"

  local current_raw candidate_raw
  current_raw="${artifact_dir}/current.raw.tsv"
  candidate_raw="${artifact_dir}/candidate.raw.tsv"

  log "model:         $MODEL_PATH"
  log "binary:        $LLAMA_BIN"
  log "context:       $CONTEXT"
  log "runs:          $RUNS"
  log "n_predict:     $N_PREDICT"
  log "port:          $PORT"
  log "artifacts:     $artifact_dir"

  if [ "$(health_code)" = "200" ]; then
    restore_was_live=1
    log
    log "using live current-args service on :$PORT"
    benchmark_server "current" "live-service" "$current_raw"
    log
    log "stopping live service before candidate benchmark"
    stop_live_service || die "failed to stop live llama-server service"
    if try_systemctl_start >/dev/null 2>&1; then
      # We only probed start capability to distinguish restore path; stop it again immediately.
      try_systemctl_stop >/dev/null 2>&1 || true
      restore_original_mode="systemd"
    else
      restore_original_mode="manual"
    fi
  else
    log
    log "launching current-args server on :$PORT"
    start_manual_server "$current_pid_file" "${CURRENT_ARGS[@]}"
    benchmark_server "current" "launched-binary" "$current_raw"
    stop_manual_server "$current_pid_file"
  fi

  log
  log "launching candidate-args server on :$PORT"
  start_manual_server "$candidate_pid_file" "${CANDIDATE_ARGS[@]}"
  benchmark_server "candidate" "launched-binary" "$candidate_raw"
  stop_manual_server "$candidate_pid_file"

  summarize_results "$current_raw" "$candidate_raw" "$artifact_dir"
}

main "$@"
