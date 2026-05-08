#!/usr/bin/env bash
#
# Universal AMD GPU + ROCm ("latest") installer for Ubuntu 24.04+
# Refined with robust policy checks, kernel management, and compatibility workarounds.
#

set -euo pipefail

# --- FLAGS (enable/disable steps here) ---
ROCM_VERSION="7.2.3"             # Definitive verified version for May 2026
DO_APT_UPGRADE=1
DO_OS_POLICY_CHECK=1
ALLOWED_UBUNTU_VERSIONS=("24.04")

DO_KERNEL_POLICY_CHECK=1
DO_INSTALL_MAINLINE_KERNEL=1
REQUIRED_KERNEL_MM="7.0"          # RDNA 4 (gfx1201) requires Kernel 7.0+ for stability

DO_GRUB_PARAMS=0                  # Add GRUB params (conservatively disabled by default)
GRUB_PARAMS=("amdgpu.gpu_recovery=1" "amdgpu.runpm=0" "amdgpu.ppfeaturemask=0xffffffff")

DO_PURGE_OLD_PACKAGES=1           # Remove old rocm/amdgpu/hip packages (best effort)
DO_SETUP_ROCM_REPO=1              # Add ROCm repository
DO_INSTALL_ROCM=1                 # Install rocm-dev/rocm-libs/...
DO_LINK_OPT_ROCM=1                # Make /opt/rocm -> /opt/rocm-X.Y.Z (if found)

DO_USER_GROUPS=1                  # Add user to render,video
DO_BASHRC_PATH=1                  # Add /opt/rocm/bin to PATH via ~/.bashrc

DO_OLLAMA_AMDGPU_IDS_WORKAROUND=1 # Create amdgpu.ids link for some Ollama builds
DO_GPU_POWER_CONTROL_ON=1         # Best effort: set power/control=on (if available)

# --- Colors for output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# --- Start ---
print_info "Starting AMD ROCm installation..."

# Dependency checks
for cmd in lspci wget gpg curl lsb_release; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    print_error "Missing dependency: $cmd"
    exit 1
  fi
done

# Check this is Ubuntu
. /etc/os-release
if [[ "${ID:-}" != "ubuntu" ]]; then
  print_error "This script is intended for Ubuntu. Exiting."
  exit 1
fi

# Restrict script to specific Ubuntu releases (only 24.04)
if [[ "${DO_OS_POLICY_CHECK}" -eq 1 ]]; then
  UBUNTU_VERSION="$(lsb_release -rs)"
  ok=0
  for v in "${ALLOWED_UBUNTU_VERSIONS[@]}"; do
    if [[ "${UBUNTU_VERSION}" == "${v}" ]]; then
      ok=1
      break
    fi
  done

  if [[ "${ok}" -ne 1 ]]; then
    print_error "Unsupported Ubuntu version: ${UBUNTU_VERSION}"
    print_error "Allowed versions: ${ALLOWED_UBUNTU_VERSIONS[*]}"
    exit 1
  fi
fi

# Detect AMD GPU (vendor 1002)
AMD_GPU_LINES="$(lspci -nn | grep -iE 'vga|3d' | grep -i '1002:' || true)"
if [[ -z "${AMD_GPU_LINES}" ]]; then
  print_warning "No AMD GPU detected (vendor 1002). This is unusual for a ROCm installation."
  read -p "Continue anyway? (y/N) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      exit 1
  fi
else
  print_info "AMD GPUs detected:"
  echo "${AMD_GPU_LINES}"
fi

# Best effort: purge old packages/repos
if [[ "${DO_PURGE_OLD_PACKAGES}" -eq 1 ]]; then
  print_info "Removing previous ROCm/AMDGPU packages and clearing cache..."
  sudo dpkg --configure -a || true
  sudo rm -rf /etc/apt/sources.list.d/amdgpu* /etc/apt/sources.list.d/rocm* /etc/apt/sources.list.d/graphics* || true
  sudo apt update || true
  sudo apt remove --purge -y rocminfo || true
  sudo apt purge -y 'rocm*' 'amdgpu*' 'graphics*' 'hip*' || true
  sudo apt autoremove -y || true
  sudo apt clean
else
  print_info "Skipping purge old packages (DO_PURGE_OLD_PACKAGES=0)."
fi

# Update/upgrade
if [[ "${DO_APT_UPGRADE}" -eq 1 ]]; then
  print_info "Running apt update & upgrade..."
  sudo apt update
  sudo apt upgrade -y
fi

# Kernel check/upgrade (script policy)
KERNEL_INSTALLED=0
print_info "Current kernel: $(uname -r)"

if [[ "${DO_KERNEL_POLICY_CHECK}" -eq 1 ]]; then
  KERNEL_VERSION="$(uname -r)"
  KERNEL_MM="$(echo "${KERNEL_VERSION}" | sed -nE 's/^([0-9]+)\.([0-9]+).*/\1.\2/p')"
  
  if [[ -z "${KERNEL_MM}" ]]; then
    print_warning "Could not parse kernel version. Skipping kernel policy check."
  else
    req_major="${REQUIRED_KERNEL_MM%.*}"
    req_minor="${REQUIRED_KERNEL_MM#*.}"
    cur_major="${KERNEL_MM%.*}"
    cur_minor="${KERNEL_MM#*.}"

    print_info "Checking kernel policy: ${KERNEL_MM} vs required ${REQUIRED_KERNEL_MM}"

    KERNEL_OK=0
    if [[ "${cur_major}" -gt "${req_major}" ]] || \
       [[ "${cur_major}" -eq "${req_major}" && "${cur_minor}" -ge "${req_minor}" ]]; then
      KERNEL_OK=1
    fi

    if [[ "${KERNEL_OK}" -ne 1 ]]; then
      print_warning "Kernel is older than required by this script policy (>= ${REQUIRED_KERNEL_MM})."
      if [[ "${DO_INSTALL_MAINLINE_KERNEL}" -eq 1 ]]; then
        print_info "Installing latest mainline kernel..."
        sudo add-apt-repository ppa:cappelikan/ppa -y 2>/dev/null || true
        sudo apt update
        sudo apt install -y mainline pkexec
        sudo mainline install-latest
        print_success "Mainline kernel installed. Reboot required to activate it."
        KERNEL_INSTALLED=1
      else
        print_warning "Mainline kernel install is disabled by flag DO_INSTALL_MAINLINE_KERNEL=0. Continuing."
      fi
    fi
  fi
fi

# Optional: GRUB parameters (append-only)
if [[ "${DO_GRUB_PARAMS}" -eq 1 ]]; then
  GRUB_FILE="/etc/default/grub"
  GRUB_CHANGED=0

  for param in "${GRUB_PARAMS[@]}"; do
    if ! sudo grep -qE "GRUB_CMDLINE_LINUX_DEFAULT=.*\b${param}\b" "${GRUB_FILE}"; then
      sudo cp -a "${GRUB_FILE}" "${GRUB_FILE}.backup.$(date +%F-%H%M%S)"
      sudo sed -i -E "s/^(GRUB_CMDLINE_LINUX_DEFAULT=\")([^\"]*)\"/\1\2 ${param}\"/" "${GRUB_FILE}"
      print_info "Added GRUB param: ${param}"
      GRUB_CHANGED=1
    else
      print_info "GRUB param already present: ${param}"
    fi
  done

  if [[ "${GRUB_CHANGED}" -eq 1 ]]; then
    sudo update-grub
    print_success "GRUB updated."
  fi
else
  print_info "Skipping GRUB parameters (DO_GRUB_PARAMS=0)."
fi

# Add ROCm repository
if [[ "${DO_SETUP_ROCM_REPO}" -eq 1 ]]; then
  . /etc/os-release
  UBUNTU_CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
  if [[ -z "${UBUNTU_CODENAME}" ]]; then
    print_error "Cannot detect Ubuntu codename (UBUNTU_CODENAME/VERSION_CODENAME)."
    exit 1
  fi

  print_info "Testing ROCm repository connectivity..."
  # Auto-discovery if the primary choice fails
  # Using a more robust grep for "200" status code (HTTP/2 often omits "OK")
  if ! curl -s -I "https://repo.radeon.com/rocm/apt/${ROCM_VERSION}/dists/${UBUNTU_CODENAME}/Release" | grep -qE "HTTP/.* (200|302)"; then
    print_warning "ROCm ${ROCM_VERSION} repo not found for ${UBUNTU_CODENAME}. Starting auto-discovery..."
    FOUND_VERSION=""
    # Check these in order of preference
    for v in "latest" "7.2.3" "7.2.2" "7.2.1" "7.2" "7.1" "7.0"; do
      print_info "Checking ROCm version: ${v}..."
      if curl -s -I "https://repo.radeon.com/rocm/apt/${v}/dists/${UBUNTU_CODENAME}/Release" | grep -qE "HTTP/.* (200|302)"; then
        print_success "Found working ROCm version: ${v}"
        FOUND_VERSION="${v}"
        break
      fi
    done

    if [[ -z "${FOUND_VERSION}" ]]; then
      print_error "No working ROCm repository found for ${UBUNTU_CODENAME}."
      exit 1
    fi
    ROCM_VERSION="${FOUND_VERSION}"
  fi

  print_info "Setting up ROCm '${ROCM_VERSION}' repository and pinning..."

  sudo install -d -m 0755 /etc/apt/keyrings
  wget -qO- https://repo.radeon.com/rocm/rocm.gpg.key \
    | gpg --dearmor \
    | sudo tee /etc/apt/keyrings/rocm.gpg >/dev/null

  echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/${ROCM_VERSION}/ ${UBUNTU_CODENAME} main" \
    | sudo tee /etc/apt/sources.list.d/rocm.list >/dev/null

  # Pin repo.radeon.com above Ubuntu (priority 1000 to ensure override of local versions)
  sudo tee /etc/apt/preferences.d/rocm-pin-1000 >/dev/null <<'EOF'
Package: *
Pin: release o=repo.radeon.com
Pin-Priority: 1000
EOF

else
  print_info "Skipping ROCm repo setup (DO_SETUP_ROCM_REPO=0)."
fi

# Install ROCm packages
if [[ "${DO_INSTALL_ROCM}" -eq 1 ]]; then
  print_info "Installing ROCm stack using official amdgpu-install tool..."
  
  INSTALLER_DEB="amdgpu-install_${ROCM_VERSION}.70203-1_all.deb"
  INSTALLER_URL="https://repo.radeon.com/amdgpu-install/${ROCM_VERSION}/ubuntu/noble/${INSTALLER_DEB}"
  
  wget -q "${INSTALLER_URL}" -O "/tmp/${INSTALLER_DEB}"
  sudo apt install -y "/tmp/${INSTALLER_DEB}"
  
  # Run the installer for the rocm usecase
  # --usecase=rocm installs the full stack for compute
  # --no-dkms is NOT used here because RDNA 4 (gfx1201) often needs the newer driver modules
  sudo amdgpu-install -y --usecase=rocm --no-introspect
else
  print_info "Skipping ROCm install (DO_INSTALL_ROCM=0)."
fi

# /opt/rocm -> /opt/rocm-X.Y.Z
if [[ "${DO_LINK_OPT_ROCM}" -eq 1 ]]; then
  INSTALLED_ROCM_DIR="$(ls -d /opt/rocm-[0-9]* 2>/dev/null | sort -V | tail -n 1 || true)"
  if [[ -n "${INSTALLED_ROCM_DIR}" ]]; then
    REAL_VERSION="$(echo "${INSTALLED_ROCM_DIR}" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo latest)"
    sudo ln -sfn "${INSTALLED_ROCM_DIR}" /opt/rocm
    print_success "ROCm detected: ${REAL_VERSION} (${INSTALLED_ROCM_DIR}); linked /opt/rocm -> ${INSTALLED_ROCM_DIR}"
  else
    print_warning "No /opt/rocm-X.Y.Z directory found; leaving /opt/rocm as-is."
  fi
else
  print_info "Skipping /opt/rocm symlink (DO_LINK_OPT_ROCM=0)."
fi

# User groups: render,video (required for GPU access)
if [[ "${DO_USER_GROUPS}" -eq 1 ]]; then
  # Detect the actual user if running under sudo
  REAL_USER="${SUDO_USER:-$(whoami)}"
  if [[ "${REAL_USER}" == "root" ]]; then
    print_warning "Script is running as root and SUDO_USER is not set. Cannot automatically add user to groups."
  else
    print_info "Adding user '${REAL_USER}' to render and video groups..."
    sudo usermod -aG render,video "${REAL_USER}"
    print_success "User '${REAL_USER}' added to groups: render, video."
  fi
else
  print_info "Skipping user groups (DO_USER_GROUPS=0)."
fi

# PATH + LD_LIBRARY_PATH in ~/.bashrc
if [[ "${DO_BASHRC_PATH}" -eq 1 ]]; then
  TARGET_USER="${SUDO_USER:-$USER}"
  TARGET_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
  TARGET_BASHRC="${TARGET_HOME}/.bashrc"
  MARKER="AMD ROCm Paths"

  if [[ ! -f "${TARGET_BASHRC}" ]]; then
    sudo -u "${TARGET_USER}" touch "${TARGET_BASHRC}" || true
  fi

  if ! grep -q "${MARKER}" "${TARGET_BASHRC}" 2>/dev/null; then
    cat >> "${TARGET_BASHRC}" <<EOF

# ${MARKER}
if [ -d "/opt/rocm" ]; then
  export PATH="/opt/rocm/bin:\$PATH"
  export LD_LIBRARY_PATH="/opt/rocm/lib:\$LD_LIBRARY_PATH"
  export ROCM_PATH="/opt/rocm"
  export HIP_CLANG_PATH="/opt/rocm/llvm/bin"
fi
EOF
    print_success "Added ROCm paths to ${TARGET_BASHRC}"
  else
    print_info "ROCm PATH block already present in ${TARGET_BASHRC}"
  fi
else
  print_info "Skipping .bashrc PATH (DO_BASHRC_PATH=0)."
fi

# Workaround for amdgpu.ids (some Ollama builds)
if [[ "${DO_OLLAMA_AMDGPU_IDS_WORKAROUND}" -eq 1 ]]; then
  if [[ -f /usr/share/libdrm/amdgpu.ids ]]; then
    sudo mkdir -p /opt/amdgpu/share/libdrm
    sudo ln -sf /usr/share/libdrm/amdgpu.ids /opt/amdgpu/share/libdrm/amdgpu.ids
    print_success "Created compatibility link for amdgpu.ids"
  fi
fi

# Best effort: power/control=on
if [[ "${DO_GPU_POWER_CONTROL_ON}" -eq 1 ]]; then
  if [[ -w /sys/class/drm/card0/device/power/control ]]; then
    echo on | sudo tee /sys/class/drm/card0/device/power/control >/dev/null
    print_success "Set /sys/class/drm/card0/device/power/control = on"
  fi
fi

# Final
print_success "Installation finished."
if [[ "${KERNEL_INSTALLED}" -eq 1 ]]; then
  print_warning "REBOOT REQUIRED to activate the new kernel."
else
  print_info "Reboot recommended to apply group membership changes."
fi

print_info "After reboot, verify with: rocminfo"
