#!/usr/bin/env bash
# Export Autodesk registry keys directly from the mounted Windows registry
# hives. The generated registry/autodesk-full.reg remains gitignored.

set -euo pipefail
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

if [[ $# -ge 1 ]]; then
    WINDOWS_MOUNT="$1"
fi

if ! command -v hivexregedit >/dev/null 2>&1; then
    echo "ERROR: hivexregedit not found." >&2
    echo "       Ubuntu 22.04: sudo apt install libhivex-bin" >&2
    echo "       Or run: bash scripts/phase0-setup.sh" >&2
    exit 1
fi

if [[ ! -d "$WINDOWS_MOUNT/Windows" ]]; then
    echo "ERROR: Windows installation not found at: $WINDOWS_MOUNT" >&2
    echo "       Mount/expose the Windows filesystem there or set WINDOWS_MOUNT in inventor.env." >&2
    exit 1
fi

WIN_USER="$(detect_windows_user || true)"
if [[ -z "$WIN_USER" ]]; then
    echo "ERROR: Could not auto-detect a Windows user under $WINDOWS_MOUNT/Users." >&2
    echo "       Set WINDOWS_USER in inventor.env." >&2
    exit 1
fi

SOFTWARE_HIVE="$WINDOWS_MOUNT/Windows/System32/config/SOFTWARE"
NTUSER_HIVE="$WINDOWS_MOUNT/Users/$WIN_USER/NTUSER.DAT"
OUTPUT="$PROJECT_DIR/registry/autodesk-full.reg"

for hive in "$SOFTWARE_HIVE" "$NTUSER_HIVE"; do
    [[ -f "$hive" ]] || { echo "ERROR: Registry hive not found: $hive" >&2; exit 1; }
done

mkdir -p "$(dirname "$OUTPUT")"

echo "=== Autodesk registry export ==="
echo "Windows source: $WINDOWS_MOUNT"
echo "Windows user:   $WIN_USER"
echo "Output:         $OUTPUT"

{
    printf 'Windows Registry Editor Version 5.00\r\n\r\n'

    echo "[1/2] Exporting HKLM\\SOFTWARE\\Autodesk..." >&2
    if hivexregedit --export "$SOFTWARE_HIVE" '\Autodesk' 2>/dev/null \
            | sed 's|^\[\\|[HKEY_LOCAL_MACHINE\\SOFTWARE\\|'; then
        echo "      OK" >&2
    else
        echo "      WARNING: HKLM Autodesk export failed or keys were absent" >&2
    fi

    echo "[2/2] Exporting HKCU\\Software\\Autodesk..." >&2
    if hivexregedit --export "$NTUSER_HIVE" '\Software\Autodesk' 2>/dev/null \
            | sed 's|^\[\\Software\\|[HKEY_CURRENT_USER\\Software\\|'; then
        echo "      OK" >&2
    else
        echo "      WARNING: HKCU Autodesk export failed or keys were absent" >&2
    fi
} > "$OUTPUT"

echo "Export complete: $(wc -l < "$OUTPUT") lines"
echo "Next: bash scripts/rebuild-prefix.sh"
