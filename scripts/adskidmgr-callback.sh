#!/usr/bin/env bash
# Handle adskidmgr:// protocol callbacks from the browser without stopping the
# running Wine server.
set -euo pipefail
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"
require_wine

mkdir -p "$LOGDIR"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
CALLBACK_LOG="$LOGDIR/adskidmgr-callback-$TIMESTAMP-$$.log"

log() {
    printf '%s\n' "$*" >>"$CALLBACK_LOG"
}

prepare_callback_display() {
    if ! detect_graphical_session; then
        log "ERROR: No graphical DISPLAY could be resolved for the Autodesk callback."
        return 1
    fi

    local active_xauthority="${XAUTHORITY:-}"
    local standard_xauthority="$HOME/.Xauthority"

    # Firefox Snap and desktop-portal launches work most reliably with the
    # conventional ~/.Xauthority path. If the Inventor headless session uses a
    # custom authority file, copy its current cookie into ~/.Xauthority.
    if [[ -n "$active_xauthority" &&
          "$active_xauthority" != "$standard_xauthority" &&
          -r "$active_xauthority" &&
          -n "$(command -v xauth 2>/dev/null || true)" ]]; then

        touch "$standard_xauthority"
        chmod 600 "$standard_xauthority"

        if xauth -f "$active_xauthority" nlist |
            xauth -f "$standard_xauthority" nmerge - >/dev/null 2>&1; then
            export XAUTHORITY="$standard_xauthority"
        fi
    elif [[ -r "$standard_xauthority" ]]; then
        export XAUTHORITY="$standard_xauthority"
    fi

    if command -v xdpyinfo >/dev/null 2>&1; then
        if ! xdpyinfo >/dev/null 2>&1; then
            log "ERROR: X display authentication failed."
            log "DISPLAY=${DISPLAY:-<unset>}"
            log "XAUTHORITY=${XAUTHORITY:-<unset>}"
            return 1
        fi
    fi

    return 0
}

uri="${1:-}"
if [[ -z "$uri" || "$uri" != adskidmgr://* ]]; then
    log "ERROR: Expected an adskidmgr:// callback URI."
    exit 2
fi

# Do not write the callback URI itself to disk. It can contain an OAuth
# authorization code or other short-lived authentication material.
log "=== Autodesk Identity Manager callback ==="
log "Timestamp: $(date --iso-8601=seconds)"
log "URI: received and validated (redacted)"
log "URI length: ${#uri}"

if ! prepare_callback_display; then
    exit 1
fi

log "DISPLAY=${DISPLAY:-<unset>}"
log "XAUTHORITY=${XAUTHORITY:-<unset>}"
log "WINEPREFIX=$WINEPREFIX"

IDSDK_USER="$(printf '%s' "$USER" | od -An -tx1 | tr -d ' \n' | tr '[:lower:]' '[:upper:]')"
IPCDIR="$WINEPREFIX/drive_c/ProgramData/Autodesk/IDSDK/$IDSDK_USER/interprocess/01000000"
mkdir -p "$IPCDIR"

shopt -s nullglob
quit_files=("$IPCDIR"/IDSDKQuit-v2-*)
log "IDSDKQuit files before callback: ${#quit_files[@]}"

for f in "${quit_files[@]}"; do
    pid="$(basename "$f" | grep -oP 'v2-\K[0-9]+' || true)"
    if [[ -n "$pid" && ! -f "$IPCDIR/AdOAuth2Code-$pid" ]]; then
        printf '\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00' \
            > "$IPCDIR/AdOAuth2Code-$pid"
        log "Created IDSDK OAuth IPC marker for PID $pid"
    fi
done

IDENTITY_EXE='C:\Program Files\Autodesk\AdskIdentityManager\Current\AdskIdentityManager.exe'

log "Starting Autodesk Identity Manager callback process..."

(
    set +e
    "$WINE_BIN" "$IDENTITY_EXE" "$uri"
    status=$?
    printf 'Identity Manager callback exit status: %d\n' "$status"
) >>"$CALLBACK_LOG" 2>&1 &

callback_pid=$!
log "Callback process PID: $callback_pid"
log "Callback log: $CALLBACK_LOG"

exit 0
