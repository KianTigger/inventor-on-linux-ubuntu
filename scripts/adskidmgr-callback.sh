#!/usr/bin/env bash
# Handle adskidmgr:// protocol callbacks from the browser without stopping the
# running Wine server.
set -euo pipefail
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"
require_wine

uri="${1:-}"
if [[ -z "$uri" || "$uri" != adskidmgr://* ]]; then
    echo "ERROR: Expected an adskidmgr:// callback URI." >&2
    exit 2
fi

IDSDK_USER="$(printf '%s' "$USER" | od -An -tx1 | tr -d ' \n' | tr '[:lower:]' '[:upper:]')"
IPCDIR="$WINEPREFIX/drive_c/ProgramData/Autodesk/IDSDK/$IDSDK_USER/interprocess/01000000"
mkdir -p "$IPCDIR"

shopt -s nullglob
for f in "$IPCDIR"/IDSDKQuit-v2-*; do
    pid="$(basename "$f" | grep -oP 'v2-\K[0-9]+' || true)"
    if [[ -n "$pid" && ! -f "$IPCDIR/AdOAuth2Code-$pid" ]]; then
        printf '\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00' \
            > "$IPCDIR/AdOAuth2Code-$pid"
    fi
done

nohup "$WINE_BIN" \
    'C:\Program Files\Autodesk\AdskIdentityManager\Current\AdskIdentityManager.exe' \
    "$uri" >/dev/null 2>&1 &
