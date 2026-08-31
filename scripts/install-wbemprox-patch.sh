#!/usr/bin/env bash
# Build the repository's Win32_TimeZone wbemprox patch against Wine 11.4 and
# install the resulting DLL into the active WineHQ development installation.

set -euo pipefail
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"
require_wine
require_command patch "Install prerequisites with scripts/phase0-setup.sh"
require_command make "Install prerequisites with scripts/phase0-setup.sh"
require_command curl "Install prerequisites with scripts/phase0-setup.sh"

if [[ $EUID -eq 0 ]]; then
    echo "ERROR: Run as your normal user; the script uses sudo only for final DLL installation." >&2
    exit 1
fi

PATCH_FILE="$PROJECT_DIR/patches/wbemprox-timezone.patch"
[[ -f "$PATCH_FILE" ]] || { echo "ERROR: Missing $PATCH_FILE" >&2; exit 1; }

BUILD_ROOT="${WBEMPROX_BUILD_ROOT:-$HOME/.cache/inventor-on-linux/wine-$WINE_VERSION-wbemprox}"
SOURCE_DIR="$BUILD_ROOT/wine-$WINE_VERSION"
ARCHIVE="$BUILD_ROOT/wine-$WINE_VERSION.tar.xz"
mkdir -p "$BUILD_ROOT"

if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "Downloading Wine $WINE_VERSION source..."
    curl -fL --retry 3 \
        "https://dl.winehq.org/wine/source/11.x/wine-$WINE_VERSION.tar.xz" \
        -o "$ARCHIVE"
    tar -xJf "$ARCHIVE" -C "$BUILD_ROOT"
fi

cd "$SOURCE_DIR"
if patch --dry-run -p1 < "$PATCH_FILE" >/dev/null 2>&1; then
    patch -p1 < "$PATCH_FILE"
elif patch --dry-run -R -p1 < "$PATCH_FILE" >/dev/null 2>&1; then
    echo "wbemprox patch is already applied to the cached source tree."
else
    echo "ERROR: wbemprox patch does not apply cleanly to Wine $WINE_VERSION source." >&2
    exit 1
fi

if [[ ! -f Makefile ]]; then
    echo "Configuring minimal Wine build tree..."
    ./configure --enable-win64 --without-x --without-freetype --without-fontconfig \
        --without-gstreamer --without-vulkan --without-opengl --without-alsa \
        --without-pulse --without-cups --without-dbus --without-usb \
        --without-v4l2 --without-wayland
fi

echo "Building wbemprox.dll..."
make -C dlls/wbemprox -j"$(nproc)"

BUILT_DLL="$SOURCE_DIR/dlls/wbemprox/x86_64-windows/wbemprox.dll"
[[ -f "$BUILT_DLL" ]] || BUILT_DLL="$(find "$SOURCE_DIR/dlls/wbemprox" -type f -path '*/x86_64-windows/wbemprox.dll' -print -quit)"
[[ -f "$BUILT_DLL" ]] || { echo "ERROR: Built wbemprox.dll was not found." >&2; exit 1; }

WINE_REAL="$(readlink -f "$WINE_BIN")"
WINE_ROOT="$(cd "$(dirname "$WINE_REAL")/.." && pwd)"
SYSTEM_DLL="$(find "$WINE_ROOT" -type f -path '*/x86_64-windows/wbemprox.dll' -print -quit 2>/dev/null || true)"
if [[ -z "$SYSTEM_DLL" ]]; then
    echo "ERROR: Could not locate WineHQ's installed x86_64-windows/wbemprox.dll under $WINE_ROOT." >&2
    exit 1
fi

echo "Installing patched DLL to: $SYSTEM_DLL"
if [[ ! -f "$SYSTEM_DLL.inventor-original" ]]; then
    sudo cp -a "$SYSTEM_DLL" "$SYSTEM_DLL.inventor-original"
fi
sudo install -m 0644 "$BUILT_DLL" "$SYSTEM_DLL"

echo "wbemprox patch installed. Original preserved as: $SYSTEM_DLL.inventor-original"
echo "Wine packages are held by phase0-setup.sh so an unattended upgrade does not overwrite this patch."
