#!/usr/bin/env bash
# Alternative installation path for a pre-built Wine prefix archive.
# The preferred/reproducible path is rebuild-prefix.sh from a Windows source.

set -euo pipefail
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"
require_wine

if [[ $EUID -eq 0 ]]; then
    echo "ERROR: Run as the Linux user who will run Inventor, not root." >&2
    exit 1
fi

TARBALL="${1:-$PROJECT_DIR/wine-prefix-inventor2026.tar.zst}"
if [[ ! -f "$TARBALL" ]]; then
    alt="$(find "$PROJECT_DIR" -maxdepth 1 -type f -name '*FULL*.tar.zst' -print -quit 2>/dev/null || true)"
    [[ -n "$alt" ]] && TARBALL="$alt"
fi
[[ -f "$TARBALL" ]] || {
    echo "ERROR: Wine prefix archive not found." >&2
    echo "Usage: bash scripts/install-on-new-machine.sh /path/to/wine-prefix-inventor2026.tar.zst" >&2
    exit 1
}

if [[ -d "$WINEPREFIX" ]]; then
    read -r -p "Existing prefix $WINEPREFIX will be replaced. Type INSTALL to continue: " answer
    [[ "$answer" == INSTALL ]] || { echo "Aborted."; exit 1; }
    "$WINESERVER_BIN" -k >/dev/null 2>&1 || true
    rm -rf "$WINEPREFIX"
fi

echo "Extracting prefix archive: $TARBALL"
tar --zstd -xf "$TARBALL" -C "$HOME"
[[ -f "$WINEPREFIX/drive_c/Program Files/Autodesk/Inventor 2026/Bin/Inventor.exe" ]] || {
    echo "ERROR: Archive did not create the expected prefix at $WINEPREFIX." >&2
    exit 1
}

bash "$SCRIPT_DIR/install-dxvk-prefix.sh"
bash "$SCRIPT_DIR/install-wbemprox-patch.sh"

rm -f "$WINEPREFIX/dosdevices/d:" 2>/dev/null || true
if [[ -n "${DATA_DRIVE:-}" && -d "$DATA_DRIVE" ]]; then
    ln -s "$DATA_DRIVE" "$WINEPREFIX/dosdevices/d:"
fi

bash "$SCRIPT_DIR/setup-user-integration.sh"

echo "Pre-built prefix installation complete."
echo "Run: bash scripts/doctor.sh"
echo "Then: bash scripts/launch-inventor.sh"
