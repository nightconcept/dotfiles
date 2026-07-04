#!/usr/bin/env bash

set -euo pipefail

SECRETS_PATH="/etc/mog-secrets"
DEFAULT_USERNAME="danny"
DEFAULT_DOMAIN="mog"

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo "Run as root: sudo $0" >&2
    exit 1
fi

read -r -p "Username [$DEFAULT_USERNAME]: " username
username=${username:-$DEFAULT_USERNAME}

read -r -p "Domain [$DEFAULT_DOMAIN]: " domain
domain=${domain:-$DEFAULT_DOMAIN}

while true; do
    read -r -s -p "SMB password: " password
    echo
    read -r -s -p "Confirm password: " password_confirm
    echo

    if [[ -z "$password" ]]; then
        echo "Password cannot be empty." >&2
        continue
    fi

    if [[ "$password" != "$password_confirm" ]]; then
        echo "Passwords do not match. Try again." >&2
        continue
    fi

    break
done

tmp_file=$(mktemp)
trap 'rm -f "$tmp_file"' EXIT

cat > "$tmp_file" <<EOF
username=$username
domain=$domain
password=$password
EOF

install -m 600 "$tmp_file" "$SECRETS_PATH"

echo "Wrote $SECRETS_PATH with mode 600."
