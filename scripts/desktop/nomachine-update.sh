#!/usr/bin/env bash
set -euo pipefail

if (( EUID != 0 )); then
  exec sudo -- /bin/bash "$(realpath -- "$0")" "$@"
fi

nx_system=/usr/NX
if [[ ! -x "$nx_system/bin/nxupdatecli" ]]; then
  printf '%s\n' 'The installed NoMachine CLI updater was not found.' >&2
  exit 1
fi

# Give the updater a private directory for its per-run logs.
update_dir=$(mktemp -d)
trap 'find "$update_dir" -depth -delete' EXIT

# EOF skips the updater's keypress prompts. Capture its output because a
# concurrent vendor updater can make it print "up to date" and exit zero.
update_status=0
LC_ALL=C env NX_SYSTEM="$nx_system" NX_ROOT="$update_dir" NX_CONFIG="$update_dir" \
  LD_LIBRARY_PATH="$nx_system/lib" \
  "$nx_system/bin/nxupdatecli" --upgrade </dev/null 2>&1 |
  tee "$update_dir/output.log" || update_status=$?

if grep -Fq 'Going to ignore the update because another one is running' "$update_dir/output.log"; then
  printf '%s\n' 'NoMachine skipped the upgrade because another updater is running.' >&2
  exit 75
fi

if (( update_status != 0 )); then
  exit "$update_status"
fi

systemctl is-active nxserver.service
