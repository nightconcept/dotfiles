#!/usr/bin/env bash
# Internal pyinfra implementation. This is not a separate deployment entrypoint.
set -euo pipefail
umask 077

repo_dir=$1
repo_url=$2
commit=$3
python_version=$4
shift 4

: "${HERMES_HOME:?HERMES_HOME must identify the persistent Hermes state directory}"
unset PYTHONPATH PYTHONHOME VIRTUAL_ENV UV_PYTHON
export UV_PROJECT_ENVIRONMENT="$repo_dir/venv"

mkdir -p "$(dirname "$repo_dir")" "$HERMES_HOME"
exec 9>"$HERMES_HOME/.dotfiles-install.lock"
flock -n 9 || { echo "Another Hermes deploy is running." >&2; exit 1; }

fresh=false
if [ ! -d "$repo_dir/.git" ]; then
    if [ -e "$repo_dir" ]; then
        echo "Hermes install path exists without a Git checkout; refusing to replace it." >&2
        exit 1
    fi
    git clone --quiet --no-checkout "$repo_url" "$repo_dir"
    fresh=true
fi
cd "$repo_dir"

# Never discard edits, even when HEAD already matches the pin.
if [ "$fresh" = false ] && { ! git diff --quiet || ! git diff --cached --quiet; }; then
    echo "Hermes has local changes; commit or save them before deploying." >&2
    exit 1
fi
if ! git cat-file -e "$commit^{commit}" 2>/dev/null; then
    git fetch --quiet origin "$commit"
fi
previous=$(git rev-parse --verify HEAD 2>/dev/null || true)
if [ "$fresh" = true ]; then previous=""; fi
if [ -n "$previous" ] && [ "$previous" != "$commit" ] \
    && git merge-base --is-ancestor "$commit" "$previous"; then
    echo "Refusing Hermes downgrade: restore compatible state and source before redeploying." >&2
    exit 1
fi

marker="$HERMES_HOME/.dotfiles-runtime"
identity=$(printf '%s\n' "$commit" "$python_version" "$@" | sha256sum | cut -d ' ' -f 1)
sync_args=(--locked --inexact --no-dev --python "$python_version")
for extra in "$@"; do
    sync_args+=(--extra "$extra")
done
python="$repo_dir/venv/bin/python"
unit="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/hermes-gateway.service"
if [ "$previous" = "$commit" ] && [ -f "$marker" ] \
    && [ "$(cat "$marker")" = "$identity" ] && [ -f "$unit" ] \
    && [ -x "$python" ] && uv sync "${sync_args[@]}" --check >/dev/null 2>&1 \
    && "$python" -m hermes_cli.main --help >/dev/null 2>&1; then
    echo "Hermes already matches the pinned runtime."
    exit 0
fi

# Changing an editable checkout or its environment under a live gateway mixes versions.
if systemctl --user cat hermes-gateway.service >/dev/null 2>&1; then
    systemctl --user stop hermes-gateway.service
fi
trap 'echo "Hermes preparation failed; gateway stays stopped. Fix the error and rerun the full Terra deploy." >&2' ERR

# Adopt the existing runtime only after a successful full state backup. Upstream's
# backup CLI uses SQLite safe-copy and excludes the checkout and previous backups.
pending_backup="$HERMES_HOME/.dotfiles-upgrade-backup"
if [ -f "$pending_backup" ]; then
    test -s "$(cat "$pending_backup")/state.zip"
    echo "Keeping the state backup from the interrupted Hermes deploy."
elif [ -x "$python" ]; then
    backup_dir="$HERMES_HOME/backups/dotfiles"
    mkdir -p "$backup_dir"
    backup_dir=$(mktemp -d "$backup_dir/pre-deploy-XXXXXXXX")
    echo "Backing up Hermes state (log: $backup_dir/backup.log)."
    "$python" -m hermes_cli.main backup --output "$backup_dir/state.zip" \
        >"$backup_dir/backup.log" 2>&1
    test -s "$backup_dir/state.zip"
    printf '%s\n' "$previous" >"$backup_dir/commit"
    printf '%s\n' "$backup_dir" >"$pending_backup"
    echo "Hermes state backup saved in $backup_dir"
fi

git checkout --quiet --detach "$commit"
git submodule update --init --recursive
# Fail if the lock is stale. Never fall back to a fresh dependency resolution.
# --inexact preserves optional tools Hermes installed lazily outside the base lock.
uv sync "${sync_args[@]}"
"$python" -m hermes_cli.main --help >/dev/null
"$python" -m hermes_cli.main gateway install --force --no-start-now </dev/null
test -f "$unit"
printf '%s\n' "$identity" >"$marker.new"
mv "$marker.new" "$marker"
rm -f "$pending_backup"
trap - ERR
