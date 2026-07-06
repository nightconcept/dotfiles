"""llama-swap module for terra's local LLM routing."""

import io
import os

from pyinfra.operations import files, server, systemd

from modules.linux.module import HostModule
from modules.linux.programs.model_catalog import render_llama_swap_config

_SERVICE_UNIT = """\
[Unit]
Description=llama-swap model router
After=network.target

[Service]
Type=simple
User={user}
Environment=ROCM_PATH=/opt/rocm
Environment=LD_LIBRARY_PATH=/opt/llama-cpp:/opt/rocm/lib:/opt/rocm/lib64
ExecStart=/opt/llama-swap/llama-swap --config /etc/llama-swap/config.yaml --listen {listen}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
"""


class LlamaSwapModule(HostModule):
    """Manages llama-swap installation and service lifecycle."""

    def __init__(self):
        self.user = os.environ.get("USER", "danny")
        self.install_dir = "/opt/llama-swap"
        self.version = os.environ.get("LLAMA_SWAP_VERSION", "v235")
        self.config_dir = "/etc/llama-swap"
        self.config_path = f"{self.config_dir}/config.yaml"
        self.listen = os.environ.get("LLAMA_SWAP_LISTEN", "0.0.0.0:8080")

    def install(self):
        """Ensure target directories exist."""
        files.directory(
            name=f"Ensure {self.install_dir} exists",
            path=self.install_dir,
            present=True,
            _sudo=True,
        )
        files.directory(
            name=f"Ensure {self.config_dir} exists",
            path=self.config_dir,
            present=True,
            _sudo=True,
        )

    def update(self):
        """Install or update llama-swap from GitHub releases."""
        server.shell(
            name="Install llama-swap binary",
            commands=[
                f"""
                set -eu

                VERSION="{self.version}"
                VERSION_FILE="{self.install_dir}/VERSION"

                if [ -f "$VERSION_FILE" ] && [ "$(cat "$VERSION_FILE")" = "$VERSION" ] && [ -x "{self.install_dir}/llama-swap" ]; then
                    exit 0
                fi

                ARCH="$(uname -m)"
                case "$ARCH" in
                    x86_64|amd64) ASSET_ARCH="amd64" ;;
                    aarch64|arm64) ASSET_ARCH="arm64" ;;
                    *)
                        echo "unsupported architecture for llama-swap: $ARCH" >&2
                        exit 1
                        ;;
                esac

                ASSET="llama-swap_${{VERSION#v}}_linux_${{ASSET_ARCH}}.tar.gz"
                URL="https://github.com/mostlygeek/llama-swap/releases/download/$VERSION/$ASSET"
                TMP_DIR="$(mktemp -d)"
                trap 'rm -rf "$TMP_DIR"' EXIT

                curl -fsSL "$URL" -o "$TMP_DIR/$ASSET"
                tar -xzf "$TMP_DIR/$ASSET" -C "$TMP_DIR"
                sudo install -m 0755 "$TMP_DIR/llama-swap" "{self.install_dir}/llama-swap"
                printf '%s\\n' "$VERSION" | sudo tee "$VERSION_FILE" >/dev/null
                """
            ],
        )

        files.put(
            name="Render llama-swap config",
            src=io.StringIO(render_llama_swap_config()),
            dest=self.config_path,
            mode="644",
            _sudo=True,
        )

    def service(self):
        """Cut over the host to llama-swap on the public API port."""
        server.shell(
            name="Disable legacy llama-server service",
            commands=[
                """
                set -eu
                if systemctl list-unit-files llama-server.service >/dev/null 2>&1; then
                    sudo systemctl disable --now llama-server.service || true
                fi
                """
            ],
        )

        unit = _SERVICE_UNIT.format(user=self.user, listen=self.listen)
        files.put(
            name="Deploy llama-swap systemd unit",
            src=io.StringIO(unit),
            dest="/etc/systemd/system/llama-swap.service",
            mode="644",
            _sudo=True,
        )
        systemd.service(
            name="Enable and start llama-swap",
            service="llama-swap",
            running=True,
            enabled=True,
            daemon_reload=True,
            _sudo=True,
        )

    def remove(self):
        """Remove llama-swap binaries and config."""
        server.shell(
            name="Disable llama-swap service",
            commands=["sudo systemctl disable --now llama-swap.service || true"],
        )
        files.directory(
            name=f"Remove {self.install_dir}",
            path=self.install_dir,
            present=False,
            _sudo=True,
        )
        files.directory(
            name=f"Remove {self.config_dir}",
            path=self.config_dir,
            present=False,
            _sudo=True,
        )
