#!/usr/bin/env bash
# Install the pinned upstream DXVK release into the configured Wine prefix.

set -euo pipefail
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"
require_wine

if [[ ! -d "$WINEPREFIX/drive_c/windows/system32" ]]; then
    echo "ERROR: Wine prefix does not exist: $WINEPREFIX" >&2
    exit 1
fi
if [[ ! -f "$DXVK_DIR/x64/d3d11.dll" || ! -f "$DXVK_DIR/x64/dxgi.dll" ]]; then
    echo "ERROR: DXVK $DXVK_VERSION is not installed at $DXVK_DIR." >&2
    echo "       Run: bash scripts/phase0-setup.sh" >&2
    exit 1
fi

mkdir -p "$WINEPREFIX/drive_c/windows/system32" "$WINEPREFIX/drive_c/windows/syswow64"
cp -f "$DXVK_DIR/x64/"*.dll "$WINEPREFIX/drive_c/windows/system32/"
cp -f "$DXVK_DIR/x32/"*.dll "$WINEPREFIX/drive_c/windows/syswow64/"

for dll in d3d8 d3d9 d3d10core d3d11 dxgi; do
    "$WINE_BIN" reg add 'HKCU\Software\Wine\DllOverrides' /v "$dll" /t REG_SZ /d native /f >/dev/null
 done
# Preserve the original project's compiler override.
"$WINE_BIN" reg add 'HKCU\Software\Wine\DllOverrides' /v d3dcompiler_47 /t REG_SZ /d native /f >/dev/null

echo "DXVK $DXVK_VERSION installed into $WINEPREFIX"
