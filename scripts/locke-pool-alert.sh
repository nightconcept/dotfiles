#!/usr/bin/env bash
# Gotify alert for Locke's local-lvm thin pool (pve/data). Locke has no Nix or
# pyinfra config, so this is installed by hand; see docs/network.md.
# Alerts when data or metadata crosses the threshold, repeats daily while it
# stays above, and reports once when it recovers (same as gotify-disk-alert).
set -euo pipefail

url="${GOTIFY_URL:-http://192.168.1.185:8070}"
token_file="${TOKEN_FILE:-/etc/locke-pool-alert.token}"
threshold="${THRESHOLD:-90}"
state="/var/lib/locke-pool-alert/above"

mkdir -p "$(dirname "$state")"

send() {
  curl --fail --silent --show-error --output /dev/null \
    --form-string "title=$1" --form-string "message=$2" --form-string "priority=$3" \
    "$url/message?token=$(cat "$token_file")"
}

read -r data meta < <(lvs --noheadings -o data_percent,metadata_percent pve/data)
data=${data%.*} meta=${meta%.*}
worst=$((data > meta ? data : meta))

if ((worst >= threshold)); then
  if [[ ! -e "$state" ]] || [[ -n "$(find "$state" -mmin +1440)" ]]; then
    send "locke: thin pool pve/data is ${worst}% full" \
      "Data ${data}%, metadata ${meta}% (alert threshold ${threshold}%). VMs on local-lvm stall if the pool fills." 8
    touch "$state"
  fi
elif [[ -e "$state" ]]; then
  send "locke: thin pool pve/data recovered" "Data ${data}%, metadata ${meta}%." 4
  rm -f "$state"
fi
