#!/usr/bin/env bash
# Ubuntu 22.04 host setup for Autodesk Inventor 2026 under Wine.
# Run as your normal login user; this script invokes sudo where required.

set -euo pipefail
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

if [[ $EUID -eq 0 ]]; then
    echo "ERROR: Run this script as your normal user, not with sudo." >&2
    echo "       Correct: bash scripts/phase0-setup.sh" >&2
    exit 1
fi

if [[ ! -r /etc/os-release ]]; then
    echo "ERROR: /etc/os-release is unavailable." >&2
    exit 1
fi
# shellcheck disable=SC1091
source /etc/os-release
if [[ "${ID:-}" != "ubuntu" || "${VERSION_ID:-}" != "22.04" ]]; then
    echo "ERROR: This Ubuntu port targets Ubuntu 22.04 (Jammy)." >&2
    echo "       Detected: ${PRETTY_NAME:-unknown}" >&2
    exit 1
fi
if [[ "$(uname -m)" != "x86_64" ]]; then
    echo "ERROR: x86_64 is required; detected $(uname -m)." >&2
    exit 1
fi

kernel_major="$(uname -r | cut -d. -f1)"
if (( kernel_major < 6 )); then
    echo "ERROR: Kernel 6.x or newer is required; detected $(uname -r)." >&2
    exit 1
fi

echo "=== Inventor on Linux: Ubuntu 22.04 host setup ==="
echo "Project: $PROJECT_DIR"
echo "Wine:    $WINE_VERSION (pinned)"
echo "DXVK:    $DXVK_VERSION (pinned)"
echo

echo "[1/7] Enabling 32-bit packages..."
sudo dpkg --add-architecture i386

echo "[2/7] Enabling Ubuntu Universe and installing prerequisites..."
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y software-properties-common
sudo add-apt-repository -y universe
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates curl wget gnupg \
    libhivex-bin winetricks imagemagick rsync cabextract p7zip-full \
    desktop-file-utils xdg-utils vulkan-tools pciutils \
    libvulkan1 libvulkan1:i386 \
    build-essential bison flex patch pkg-config gcc-mingw-w64-x86-64 zstd

echo "[3/7] Configuring the official WineHQ Jammy repository..."
sudo mkdir -pm755 /etc/apt/keyrings
sudo wget -qO /etc/apt/keyrings/winehq-archive.key \
    https://dl.winehq.org/wine-builds/winehq.key
sudo wget -qO /etc/apt/sources.list.d/winehq-jammy.sources \
    https://dl.winehq.org/wine-builds/ubuntu/dists/jammy/winehq-jammy.sources
sudo apt-get update

echo "[4/7] Installing exactly Wine $WINE_VERSION..."
wine_pkg_version="$(apt-cache madison winehq-devel 2>/dev/null \
    | awk -v v="$WINE_VERSION" '$3 ~ ("^" v "(~|$)") {print $3; exit}')"
if [[ -z "$wine_pkg_version" ]]; then
    echo "ERROR: WineHQ's Jammy repository does not currently expose Wine $WINE_VERSION." >&2
    echo "       Check: apt-cache madison winehq-devel" >&2
    echo "       Do not silently substitute a newer Wine version; the wbemprox patch is tied to 11.4." >&2
    exit 1
fi
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --install-recommends \
    "winehq-devel=$wine_pkg_version"

if [[ ! -x /opt/wine-devel/bin/wine ]]; then
    echo "ERROR: WineHQ devel installed, but /opt/wine-devel/bin/wine is missing." >&2
    exit 1
fi
actual_wine="$(/opt/wine-devel/bin/wine --version)"
if [[ "$actual_wine" != wine-${WINE_VERSION}* ]]; then
    echo "ERROR: Expected Wine $WINE_VERSION, got $actual_wine." >&2
    exit 1
fi
# Prevent an unattended apt upgrade from replacing the build this project was tested with.
sudo apt-mark hold winehq-devel wine-devel wine-devel-amd64 'wine-devel-i386:i386' >/dev/null 2>&1 || true

echo "[5/7] Installing DXVK $DXVK_VERSION into the user cache..."
dxvk_parent="$(dirname "$DXVK_DIR")"
mkdir -p "$dxvk_parent"
tmp_dxvk="$(mktemp -d)"
trap 'rm -rf "$tmp_dxvk"' EXIT
curl -fL --retry 3 \
    "https://github.com/doitsujin/dxvk/releases/download/v${DXVK_VERSION}/dxvk-${DXVK_VERSION}.tar.gz" \
    -o "$tmp_dxvk/dxvk.tar.gz"
tar -xzf "$tmp_dxvk/dxvk.tar.gz" -C "$tmp_dxvk"
rm -rf "$DXVK_DIR"
mv "$tmp_dxvk/dxvk-${DXVK_VERSION}" "$DXVK_DIR"
[[ -f "$DXVK_DIR/x64/d3d11.dll" && -f "$DXVK_DIR/x64/dxgi.dll" ]] || {
    echo "ERROR: DXVK archive did not contain the expected x64 DLLs." >&2
    exit 1
}

echo "[6/7] Downloading Microsoft WebView2 Evergreen x64 installer..."
mkdir -p "$(dirname "$WEBVIEW2_INSTALLER")"
curl -fL --retry 3 \
    'https://go.microsoft.com/fwlink/p/?LinkId=2124703' \
    -o "$WEBVIEW2_INSTALLER"
if [[ ! -s "$WEBVIEW2_INSTALLER" ]]; then
    echo "ERROR: WebView2 download failed." >&2
    exit 1
fi

echo "[7/7] Running host checks..."
if command -v nvidia-smi >/dev/null 2>&1; then
    driver_version="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -n1 || true)"
    echo "  NVIDIA driver: ${driver_version:-detected}"
    driver_major="${driver_version%%.*}"
    if [[ "$driver_major" =~ ^[0-9]+$ ]] && apt-cache show "libnvidia-gl-${driver_major}:i386" >/dev/null 2>&1; then
        if ! dpkg-query -W -f='${Status}' "libnvidia-gl-${driver_major}:i386" 2>/dev/null | grep -q 'install ok installed'; then
            echo "  Installing matching 32-bit NVIDIA userspace library: libnvidia-gl-${driver_major}:i386"
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "libnvidia-gl-${driver_major}:i386"
        fi
    else
        echo "  NOTE: A matching libnvidia-gl-${driver_major}:i386 package was not found in APT."
        echo "        64-bit Inventor/DXVK can still work, but 32-bit Wine components may need matching NVIDIA userspace libraries."
    fi
fi

vulkaninfo --summary >/tmp/inventor-vulkan-summary.txt 2>&1 || {
    cat /tmp/inventor-vulkan-summary.txt >&2
    echo "ERROR: Vulkan validation failed." >&2
    exit 1
}

cat <<EOF2

=== Phase 0 complete ===
Wine:     $actual_wine
DXVK:     $DXVK_DIR
WebView2: $WEBVIEW2_INSTALLER

Next:
  1. cp inventor.env.example inventor.env
  2. Edit WINDOWS_MOUNT / GPU / display settings if needed.
  3. bash scripts/doctor.sh
  4. bash scripts/export-registry.sh
  5. bash scripts/rebuild-prefix.sh
  6. bash scripts/install-wbemprox-patch.sh
  7. bash scripts/setup-user-integration.sh
  8. bash scripts/launch-inventor.sh
EOF2
