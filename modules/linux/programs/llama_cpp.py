"""Llama.cpp module for host configuration."""

import os

from pyinfra.operations import files, git, server

from ..module import HostModule


class LlamaCppModule(HostModule):
    """Manages llama.cpp installation and ROCm-optimized builds."""

    def __init__(self):
        """Initialize llama.cpp module paths."""
        self.git_dir = os.path.expanduser("~/git/llama.cpp")
        self.build_dir = os.path.join(self.git_dir, "build-pyinfra-hip")
        self.bin_dir = "/opt/llama-cpp"
        self.local_bin = os.path.expanduser("~/.local/bin")
        self.required_rocm_packages = "rocm-dev hipblas-dev rocblas-dev rocwmma-dev"

    def install(self):
        """Ensure ROCm dev packages and llama.cpp source are present."""
        # Install the ROCm build dependencies required by upstream HIP builds.
        server.shell(
            name="Install ROCm llama.cpp build dependencies (if missing)",
            commands=[
                f"if ! dpkg -s {self.required_rocm_packages} >/dev/null 2>&1; then "
                "sudo apt-get update && "
                f"sudo apt-get install -y {self.required_rocm_packages}; fi"
            ],
        )

        # Ensure directories exist
        files.directory(
            name="Ensure /opt/llama-cpp exists",
            path=self.bin_dir,
            present=True,
            _sudo=True,
        )

        files.directory(
            name="Ensure ~/.local/bin exists",
            path=self.local_bin,
            present=True,
        )

        git.repo(
            name="Clone llama.cpp source",
            src="https://github.com/ggml-org/llama.cpp.git",
            dest=self.git_dir,
        )

    def update(self):
        """Check for latest release and build/install if newer or missing."""
        # Fetch latest version info
        server.shell(
            name="Fetch latest llama.cpp version",
            commands=[
                "URL='https://api.github.com/repos/ggml-org/llama.cpp/releases/latest'; "
                f"LATEST=$(curl -s $URL | grep tag_name | cut -d '\"' -f 4); "
                f"echo $LATEST > {self.git_dir}/LATEST_TAG"
            ],
        )

        # We use a trick: only run the heavy build shell if version mismatch
        # This keeps the pyinfra plan clean and fast
        server.shell(
            name="Build and Install llama.cpp (This takes several minutes)",
            commands=[
                f"""
                set -eu

                LATEST=$(cat {self.git_dir}/LATEST_TAG)
                V_FILE="{self.bin_dir}/VERSION"
                BIN_FILE="{self.bin_dir}/llama-cli"
                BUILD_DIR="{self.build_dir}"
                STAGE_DIR="$BUILD_DIR/stage"
                
                # Check if current install has the HIP backend library.
                HAS_HIP=false
                if [ -f "$BIN_FILE" ] && find "{self.bin_dir}" -maxdepth 1 -name 'libggml-hip.so*' | grep -q .; then
                    HAS_HIP=true
                fi

                if [ ! -f "$V_FILE" ] || [ "$(cat $V_FILE)" != "$LATEST" ] || [ "$HAS_HIP" = false ]; then
                    echo "Starting build for version $LATEST..."
                    cd {self.git_dir}
                    git fetch --tags && git checkout $LATEST
                    rm -rf "$BUILD_DIR"
                    mkdir -p "$BUILD_DIR"
                    
                    export ROCM_PATH=/opt/rocm
                    export PATH=$ROCM_PATH/bin:$PATH
                    export LD_LIBRARY_PATH="$ROCM_PATH/lib:$ROCM_PATH/lib64${{LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}}"
                    GPU_ARCH=$(rocminfo | grep -o 'gfx[0-9]\\+' | head -n 1)
                    if [ -z "$GPU_ARCH" ]; then
                        echo "Unable to detect AMD GPU architecture via rocminfo" >&2
                        exit 1
                    fi
                    
                    # Enable rocWMMA Flash Attention kernels for RDNA4 HIP builds.
                    HIPCXX="$(hipconfig -l)/clang" HIP_PATH="$(hipconfig -R)" \
                    cmake -S . -B "$BUILD_DIR" \
                          -DGGML_HIP=ON \
                          -DGGML_HIP_ROCWMMA_FATTN=ON \
                          -DGPU_TARGETS="$GPU_ARCH" \
                          -DLLAMA_BUILD_TESTS=OFF \
                          -DLLAMA_BUILD_EXAMPLES=OFF \
                          -DLLAMA_TESTS_INSTALL=OFF \
                          -DLLAMA_BUILD_TOOLS=ON \
                          -DLLAMA_BUILD_SERVER=ON \
                          -DCMAKE_BUILD_TYPE=Release \
                          -DCMAKE_INSTALL_PREFIX="$STAGE_DIR" \
                          -DCMAKE_INSTALL_BINDIR=. \
                          -DCMAKE_INSTALL_LIBDIR=. \
                          -DCMAKE_INSTALL_RPATH='$ORIGIN;/opt/rocm/lib;/opt/rocm/lib64'
                             
                    cmake --build "$BUILD_DIR" --config Release -- -j$(nproc)
                    cmake --install "$BUILD_DIR" --prefix "$STAGE_DIR"
                    
                    if [ -f "$STAGE_DIR/llama-cli" ] && find "$STAGE_DIR" -maxdepth 1 -name 'libggml-hip.so*' | grep -q .; then
                        DEVICE_LIST=$("$STAGE_DIR/llama-cli" --list-devices)
                        printf '%s\n' "$DEVICE_LIST"
                        if ! printf '%s\n' "$DEVICE_LIST" | awk 'NR > 1 && NF {{ found=1 }} END {{ exit found ? 0 : 1 }}'; then
                            echo "llama.cpp HIP build did not expose any usable devices" >&2
                            exit 1
                        fi
                        sudo rsync -a --delete --exclude VERSION "$STAGE_DIR"/ {self.bin_dir}/
                        echo "$LATEST" | sudo tee $V_FILE
                        ln -sf {self.bin_dir}/llama-cli {self.local_bin}/llama-cli
                        ln -sf {self.bin_dir}/llama-server {self.local_bin}/llama-server
                    else
                        exit 1
                    fi
                else
                    echo "Already at latest version ($LATEST)."
                fi
                """
            ],
        )

    def remove(self):
        """Remove llama.cpp binaries and source."""
        files.directory(
            name="Remove /opt/llama-cpp",
            path=self.bin_dir,
            present=False,
            _sudo=True,
        )
        server.shell(
            name="Remove symlinks",
            commands=[
                f"rm -f {self.local_bin}/llama-cli",
                f"rm -f {self.local_bin}/llama-server",
            ],
        )
