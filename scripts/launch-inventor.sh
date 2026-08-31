#!/usr/bin/env bash
# Launch Inventor 2026 with Autodesk Identity Manager and Licensing Service.
# Service order: Identity Manager -> Licensing Service -> Inventor.

set -euo pipefail
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"
require_wine
normalize_gpu_uuid

WEBVIEW2_GUID='{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
WEBVIEW2_WINE_VERSION="win8"

webview2_version() {
    local key output version
    for key in \
        "HKLM\\SOFTWARE\\WOW6432Node\\Microsoft\\EdgeUpdate\\Clients\\$WEBVIEW2_GUID" \
        "HKCU\\Software\\Microsoft\\EdgeUpdate\\Clients\\$WEBVIEW2_GUID"; do
        output="$(
            WINEDEBUG=-all \
            WINEPREFIX="$WINEPREFIX" \
            "$WINE_BIN" reg query "$key" /v pv 2>&1 || true
        )"
        version="$(
            printf '%s\n' "$output" |
                tr -d '\r' |
                awk 'tolower($1)=="pv" && toupper($2)=="REG_SZ" {print $3; exit}'
        )"
        if [[ -n "$version" && "$version" != "0.0.0.0" ]]; then
            printf '%s\n' "$version"
            return 0
        fi
    done
    return 1
}

prepare_standard_xauthority() {
    local source_xauthority="${XAUTHORITY:-}"
    local standard_xauthority="$HOME/.Xauthority"

    # Firefox on Ubuntu is normally delivered as a Snap and may not be able to
    # use a custom XAUTHORITY path such as ~/.Xauthority-inventor. Mirror the
    # active cookie into the conventional ~/.Xauthority file and use that for
    # the launcher and all child processes.
    if [[ -n "$source_xauthority" && "$source_xauthority" != "$standard_xauthority" ]]; then
        if [[ ! -r "$source_xauthority" ]]; then
            echo "ERROR: Configured XAUTHORITY is not readable:" >&2
            echo "       $source_xauthority" >&2
            return 1
        fi

        require_command xauth \
            "Install xauth or rerun scripts/setup-inventor-headless-display.sh setup"

        touch "$standard_xauthority"
        chmod 600 "$standard_xauthority"

        if ! xauth -f "$source_xauthority" nlist |
            xauth -f "$standard_xauthority" nmerge -; then
            echo "ERROR: Could not copy the active X11 authentication cookie into:" >&2
            echo "       $standard_xauthority" >&2
            return 1
        fi

        export XAUTHORITY="$standard_xauthority"
    elif [[ -z "$source_xauthority" && -r "$standard_xauthority" ]]; then
        export XAUTHORITY="$standard_xauthority"
    fi

    # Fail early if the display/cookie combination is unusable. This catches a
    # stale headless-X cookie before Autodesk or Firefox are started.
    if command -v xdpyinfo >/dev/null 2>&1; then
        if ! xdpyinfo >/dev/null 2>&1; then
            echo "ERROR: Cannot authenticate to X display ${DISPLAY:-<unset>}." >&2
            echo "       XAUTHORITY=${XAUTHORITY:-<unset>}" >&2
            return 1
        fi
    fi
}

apply_webview2_wine_compat() {
    # Wine 11.4 + current WebView2 requires an older per-application Windows
    # version while the rest of the Inventor prefix remains Windows 10.
    if ! WINEDEBUG=-all \
        WINEPREFIX="$WINEPREFIX" \
        "$WINE_BIN" reg add \
            'HKCU\Software\Wine\AppDefaults\msedgewebview2.exe' \
            /v Version \
            /t REG_SZ \
            /d "$WEBVIEW2_WINE_VERSION" \
            /f >/dev/null 2>&1; then
        echo "ERROR: Could not configure the WebView2 Wine compatibility override." >&2
        return 1
    fi

    local configured
    configured="$(
        WINEDEBUG=-all \
        WINEPREFIX="$WINEPREFIX" \
        "$WINE_BIN" reg query \
            'HKCU\Software\Wine\AppDefaults\msedgewebview2.exe' \
            /v Version \
            2>&1 |
            tr -d '\r' |
            awk 'tolower($1)=="version" && toupper($2)=="REG_SZ" {print tolower($3); exit}'
    )" || true

    if [[ "$configured" != "$WEBVIEW2_WINE_VERSION" ]]; then
        echo "ERROR: WebView2 Wine compatibility verification failed." >&2
        echo "       Expected: $WEBVIEW2_WINE_VERSION" >&2
        echo "       Found:    ${configured:-<empty>}" >&2
        return 1
    fi
}

if ! detect_graphical_session; then
    cat >&2 <<'MSG'
ERROR: No graphical DISPLAY is available to this shell.

Inventor is a GUI application. On a server, either launch from the logged-in
Linux desktop session or configure INVENTOR_DISPLAY and INVENTOR_XAUTHORITY in
inventor.env. The launcher can auto-detect a GNOME session only when that
session is owned by the same Linux user.

See README.md -> "Ubuntu server / SSH display setup".
MSG
    exit 1
fi

prepare_standard_xauthority

INVENTOR_EXE="$WINEPREFIX/drive_c/Program Files/Autodesk/Inventor 2026/Bin/Inventor.exe"
[[ -f "$INVENTOR_EXE" ]] || {
    echo "ERROR: Inventor.exe is missing from $WINEPREFIX." >&2
    echo "       Run scripts/rebuild-prefix.sh first." >&2
    exit 1
}

LICENSING_SERVICE="$WINEPREFIX/drive_c/Program Files (x86)/Common Files/Autodesk Shared/AdskLicensing/Current/AdskLicensingService/AdskLicensingService.exe"
[[ -f "$LICENSING_SERVICE" ]] || {
    echo "ERROR: Autodesk Licensing Service is missing from the Wine prefix:" >&2
    echo "       $LICENSING_SERVICE" >&2
    echo "       Run scripts/rebuild-prefix.sh first." >&2
    exit 1
}

webview_version="$(webview2_version || true)"
if [[ -z "$webview_version" ]]; then
    echo "WebView2 Runtime is not installed in this Wine prefix."
    echo "Installing it now before Autodesk Licensing starts..."
    echo
    bash "$SCRIPT_DIR/install-webview2.sh"
    webview_version="$(webview2_version || true)"
fi

if [[ -z "$webview_version" ]]; then
    echo "ERROR: WebView2 Runtime is still unavailable." >&2
    echo "       Run scripts/install-webview2.sh and inspect its log before launching Inventor." >&2
    exit 1
fi

apply_webview2_wine_compat

# Autodesk documents this as the WebView2 user-data location used by licensing.
AUTODESK_USER_ROOT="$WINEPREFIX/drive_c/users/$USER/Autodesk"
mkdir -p "$AUTODESK_USER_ROOT/AdskLicensingAgent"
chmod -R u+rwX "$AUTODESK_USER_ROOT"

mkdir -p "$LOGDIR"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
IDSDK_USER="$(printf '%s' "$USER" | od -An -tx1 | tr -d ' \n' | tr '[:lower:]' '[:upper:]')"
IDSDK_ROOT="$WINEPREFIX/drive_c/ProgramData/Autodesk/IDSDK/$IDSDK_USER/interprocess"
IDSDK_IPC="$IDSDK_ROOT/01000000"

export WINEPREFIX WINEARCH
export WINEDEBUG="${WINEDEBUG:-err+all,fixme-all}"
export DXVK_LOG_LEVEL="${DXVK_LOG_LEVEL:-info}"
export DXVK_LOG_PATH="${DXVK_LOG_PATH:-$LOGDIR}"
export WINE_LARGE_ADDRESS_AWARE="${WINE_LARGE_ADDRESS_AWARE:-1}"
# Prevent the .NET 8 msquic path from loading on Wine. Preserve any explicit
# caller override instead of overwriting it.
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-msquic=}"

cleanup() {
    echo "=== Shutting down Inventor Wine prefix ==="
    [[ -x "$WINESERVER_BIN" ]] && "$WINESERVER_BIN" -k 2>/dev/null || true
}
trap cleanup SIGTERM SIGINT EXIT

echo "=== Starting Inventor 2026 ==="
echo "Wine:     $($WINE_BIN --version)"
echo "Display:  ${DISPLAY:-unset}"
echo "X auth:   ${XAUTHORITY:-unset}"
echo "WebView2: $webview_version"
echo "WebView2 Wine mode: $WEBVIEW2_WINE_VERSION"
if [[ -n "${DXVK_FILTER_DEVICE_UUID:-}" ]]; then
    echo "GPU UUID: $DXVK_FILTER_DEVICE_UUID"
else
    echo "GPU UUID: automatic (set DXVK_FILTER_DEVICE_UUID in inventor.env to pin one GPU)"
fi
echo "Logs:     $LOGDIR"

# Clear all stale IDSDK interprocess sessions, not just one directory.
echo "[0/4] Cleaning Autodesk Identity Services IPC state..."
rm -rf "$IDSDK_ROOT"
mkdir -p "$IDSDK_IPC"

echo "[1/4] Initializing wineserver..."
"$WINEBOOT_BIN" -u >/dev/null 2>&1
sleep 2

echo "[2/4] Starting Autodesk Identity Manager..."
"$WINE_BIN" 'C:\Program Files\Autodesk\AdskIdentityManager\Current\AdskIdentityManager.exe' \
    2>&1 | tee "$LOGDIR/idmgr-$TIMESTAMP.log" &

IDSERVICES_LOG="$WINEPREFIX/drive_c/users/$USER/AppData/Local/Autodesk/Identity Services/Log/IdServices.log"
echo "    Waiting for Identity Manager..."
IDMGR_READY=0
for i in $(seq 1 30); do
    sleep 1
    if grep -q 'SSO Server is ready' "$IDSERVICES_LOG" 2>/dev/null; then
        IDMGR_READY=1
        echo "    Identity Manager ready after ${i}s"
        break
    fi
    if ! pgrep -f 'AdskIdentityManager.exe' >/dev/null 2>&1; then
        echo "    Identity Manager process exited before readiness."
        tail -n 8 "$LOGDIR/idmgr-$TIMESTAMP.log" 2>/dev/null | sed 's/^/      /'
        break
    fi
    (( i % 5 == 0 )) && echo "    ... ${i}s"
done
if (( IDMGR_READY == 0 )); then
    echo "    WARNING: Identity Manager did not report ready within 30s."
    echo "    Continuing because a cached Autodesk token may still allow licensing."
fi

echo "[3/4] Starting Autodesk Licensing Service..."
"$WINE_BIN" 'C:\Program Files (x86)\Common Files\Autodesk Shared\AdskLicensing\Current\AdskLicensingService\AdskLicensingService.exe' \
    2>&1 | tee "$LOGDIR/licensing-$TIMESTAMP.log" &
sleep 5
if pgrep -f 'AdskLicensingService.exe' >/dev/null 2>&1; then
    echo "    Licensing Service running"
else
    echo "    WARNING: Licensing Service was not detected after startup."
fi

echo "[4/4] Launching Inventor 2026..."
cd "$(dirname "$INVENTOR_EXE")"
set +e
"$WINE_BIN" Inventor.exe "$@" 2>&1 | tee "$LOGDIR/inventor-$TIMESTAMP.log"
status=${PIPESTATUS[0]}
set -e
exit "$status"
