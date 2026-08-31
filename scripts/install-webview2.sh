#!/usr/bin/env bash
# Install and verify Microsoft Edge WebView2 Runtime in the Inventor Wine prefix.
# Run from a real graphical Linux session (or with INVENTOR_DISPLAY/XAUTHORITY configured).

set -euo pipefail
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"
require_wine

WEBVIEW2_GUID='{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

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

if [[ $EUID -eq 0 ]]; then
    echo "ERROR: Run this script as the Linux user who will run Inventor, not root." >&2
    exit 1
fi

[[ -s "$WEBVIEW2_INSTALLER" ]] || {
    echo "ERROR: WebView2 installer is missing:" >&2
    echo "       $WEBVIEW2_INSTALLER" >&2
    echo "       Run: bash scripts/phase0-setup.sh" >&2
    exit 1
}

[[ -f "$WINEPREFIX/drive_c/windows/system32/cmd.exe" ]] || {
    echo "ERROR: Wine prefix is not initialized at $WINEPREFIX." >&2
    echo "       Run: bash scripts/rebuild-prefix.sh" >&2
    exit 1
}

if ! detect_graphical_session; then
    cat >&2 <<'MSG'
ERROR: WebView2 installation requires a real graphical Linux session.

Configure INVENTOR_DISPLAY and INVENTOR_XAUTHORITY in inventor.env, or run
this command from the graphical session that will be used for Inventor.

Do not use xvfb-run for the final Inventor/WebView2 setup.
MSG
    exit 1
fi

if command -v xdpyinfo >/dev/null 2>&1; then
    if ! xdpyinfo >/dev/null 2>&1; then
        echo "ERROR: DISPLAY=$DISPLAY is set, but the X display is not usable." >&2
        echo "       Check INVENTOR_DISPLAY and INVENTOR_XAUTHORITY." >&2
        exit 1
    fi
fi

current_version="$(webview2_version || true)"
if [[ -n "$current_version" && $FORCE -eq 0 ]]; then
    echo "WebView2 Runtime is already installed."
    echo "Version: $current_version"
    exit 0
fi

if [[ -n "$current_version" ]]; then
    echo "WebView2 Runtime $current_version is already registered; --force requested."
fi

mkdir -p "$LOGDIR"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG="$LOGDIR/webview2-install-$TIMESTAMP.log"

# Autodesk licensing/WebView2 needs a writable user-data directory.
AUTODESK_USER_ROOT="$WINEPREFIX/drive_c/users/$USER/Autodesk"
WEBVIEW2_USER_DATA="$AUTODESK_USER_ROOT/AdskLicensingAgent"
mkdir -p "$WEBVIEW2_USER_DATA"
chmod -R u+rwX "$AUTODESK_USER_ROOT"

echo "=== Installing Microsoft Edge WebView2 Runtime ==="
echo "Wine:      $($WINE_BIN --version)"
echo "Prefix:    $WINEPREFIX"
echo "Display:   ${DISPLAY:-unset}"
echo "Installer: $WEBVIEW2_INSTALLER"
echo "Log:       $LOG"
echo
echo "The Microsoft installer may open a graphical window."
echo

# Ensure no stale Inventor/licensing processes hold WebView2 files.
"$WINESERVER_BIN" -k >/dev/null 2>&1 || true
sleep 2

set +e
WINEDEBUG="${WINEDEBUG:-err+all,fixme-all}" \
WINEPREFIX="$WINEPREFIX" \
"$WINE_BIN" "$WEBVIEW2_INSTALLER" \
    2>&1 | tee "$LOG"
installer_status=${PIPESTATUS[0]}
set -e

echo
echo "Waiting for WebView2 Runtime registration..."

installed_version=""
for attempt in $(seq 1 30); do
    installed_version="$(webview2_version || true)"
    if [[ -n "$installed_version" ]]; then
        break
    fi
    echo "  Waiting... ($attempt/30)"
    sleep 2
done

if [[ -z "$installed_version" ]]; then
    echo "ERROR: WebView2 Runtime was not detected after installation." >&2
    echo "       Installer exit status: $installer_status" >&2
    echo "       Log: $LOG" >&2
    echo >&2
    echo "Microsoft's supported detection registry keys were not populated." >&2
    exit 1
fi

echo
echo "WebView2 Runtime installed successfully."
echo "Version: $installed_version"
if (( installer_status != 0 )); then
    echo "NOTE: Installer returned status $installer_status, but the runtime is registered and usable."
fi
