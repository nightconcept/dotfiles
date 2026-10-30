"""Apply SOPS credentials to SABnzbd without logging secrets or resetting settings."""

import json
import os
import pwd
import secrets
import subprocess
import tempfile
from pathlib import Path

from configobj import ConfigObj

STATE_DIR = Path("/var/lib/sabnzbd")
DOWNLOAD_ROOT = Path("/mnt/titan/downloads/usenet")


def configure(credentials: dict[str, str]) -> None:
    """Apply managed credentials, seeding other settings only on first start."""
    for name in ("web_username", "web_password", "newshosting_username", "newshosting_password"):
        if not isinstance(credentials.get(name), str) or not credentials[name].strip():
            raise ValueError(f"Missing or invalid SOPS field: {name}")

    account = pwd.getpwnam("danny")
    STATE_DIR.mkdir(mode=0o700, parents=True, exist_ok=True)
    config_path = STATE_DIR / "sabnzbd.ini"
    config = ConfigObj(str(config_path), encoding="utf-8")
    if not config_path.exists():
        # Shared data directories must remain traversable by the arr applications.
        categories = ("sonarr", "sonarr-anime", "radarr")
        paths = [DOWNLOAD_ROOT, DOWNLOAD_ROOT / "incomplete", DOWNLOAD_ROOT / "complete"]
        paths.extend(DOWNLOAD_ROOT / "complete" / name for name in categories)
        for path in paths:
            path.mkdir(mode=0o775, parents=True, exist_ok=True)
            path.chmod(0o775)
            os.chown(path, account.pw_uid, 100)
        config["misc"] = {
            "host": "192.168.1.112",
            "port": "8080",
            "auto_browser": "0",
            "api_key": secrets.token_hex(16),
            "nzb_key": secrets.token_hex(16),
            "inet_exposure": "0",
            "host_whitelist": ["barrett"],
            "download_dir": str(DOWNLOAD_ROOT / "incomplete"),
            "complete_dir": str(DOWNLOAD_ROOT / "complete"),
            "download_free": "5G",
            "complete_free": "5G",
            "permissions": "775",
        }
        config["categories"] = {
            name: {"name": name, "pp": "3", "dir": name}
            for name in categories
        }

    config["misc"]["username"] = credentials["web_username"]
    config["misc"]["password"] = credentials["web_password"]
    servers = config.setdefault("servers", {})
    server = servers.setdefault("news.newshosting.com", {})
    server.update(
        {
            "host": "news.newshosting.com",
            "port": "563",
            "ssl": "1",
            "ssl_verify": "3",
            "username": credentials["newshosting_username"],
            "password": credentials["newshosting_password"],
        }
    )
    server.setdefault("connections", "20")
    server.setdefault("enable", "1")

    with tempfile.NamedTemporaryFile(dir=STATE_DIR, delete=False) as output:
        temporary_path = Path(output.name)
        try:
            config.write(output)
            os.fchown(output.fileno(), account.pw_uid, 100)
            os.fchmod(output.fileno(), 0o600)
            output.flush()
            os.fsync(output.fileno())
            temporary_path.replace(config_path)
        finally:
            temporary_path.unlink(missing_ok=True)


def main() -> None:
    """Decrypt on each service start using Barrett's existing personal age key."""
    os.umask(0o077)
    result = subprocess.run(
        [
            "/home/danny/.nix-profile/bin/sops",
            "--decrypt",
            "--output-type",
            "json",
            "/etc/sabnzbd/secrets.yaml",
        ],
        env={**os.environ, "SOPS_AGE_KEY_FILE": "/home/danny/.config/sops/age/keys.txt"},
        capture_output=True,
        check=False,
    )
    if result.returncode:
        raise RuntimeError("SABnzbd SOPS decryption failed; check the encrypted file and age key")
    # Never pass plaintext credentials through pyinfra facts, argv, or logs.
    try:
        credentials = json.loads(result.stdout)
    except (ValueError, UnicodeError):
        raise RuntimeError("SABnzbd SOPS file must contain a YAML mapping") from None
    if not isinstance(credentials, dict):
        raise RuntimeError("SABnzbd SOPS file must contain a YAML mapping")
    configure(credentials)


if __name__ == "__main__":
    main()
