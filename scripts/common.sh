#!/usr/bin/env bash
# Shared configuration and helper functions for the Ubuntu port.

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="${INVENTOR_CONFIG:-$PROJECT_DIR/inventor.env}"

# Defaults can be overridden by inventor.env or the process environment.
: "${WINDOWS_MOUNT:=/mnt/windows}"
: "${WINDOWS_USER:=}"
: "${WINEPREFIX:=$HOME/.wine-inventor2026}"
: "${WINE_VERSION:=11.4}"
: "${DXVK_VERSION:=2.7.1}"
: "${ADSK_IDENTITY_VERSION:=auto}"
: "${ADSK_LICENSING_VERSION:=auto}"
: "${DATA_DRIVE:=}"
: "${DXVK_FILTER_DEVICE_UUID:=}"
: "${INVENTOR_DISPLAY:=}"
: "${INVENTOR_XAUTHORITY:=}"
: "${INVENTOR_DBUS_SESSION_BUS_ADDRESS:=}"
: "${INVENTOR_XDG_RUNTIME_DIR:=}"

if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
fi

: "${DXVK_DIR:=$HOME/.local/share/dxvk/dxvk-$DXVK_VERSION}"
: "${WEBVIEW2_INSTALLER:=$HOME/.cache/inventor-on-linux/MicrosoftEdgeWebView2RuntimeInstallerX64.exe}"
: "${LOGDIR:=$PROJECT_DIR/logs}"

export WINEPREFIX
export WINEARCH=win64

# Prefer the WineHQ development installation because this project is pinned to
# Wine 11.4. Fall back to PATH for custom/manual installations.
if [[ -x /opt/wine-devel/bin/wine ]]; then
    WINE_BIN="${WINE_BIN:-/opt/wine-devel/bin/wine}"
    WINEBOOT_BIN="${WINEBOOT_BIN:-/opt/wine-devel/bin/wineboot}"
    WINESERVER_BIN="${WINESERVER_BIN:-/opt/wine-devel/bin/wineserver}"
    WINEPATH_BIN="${WINEPATH_BIN:-/opt/wine-devel/bin/winepath}"
    WINECFG_BIN="${WINECFG_BIN:-/opt/wine-devel/bin/winecfg}"
else
    WINE_BIN="${WINE_BIN:-$(command -v wine 2>/dev/null || true)}"
    WINEBOOT_BIN="${WINEBOOT_BIN:-$(command -v wineboot 2>/dev/null || true)}"
    WINESERVER_BIN="${WINESERVER_BIN:-$(command -v wineserver 2>/dev/null || true)}"
    WINEPATH_BIN="${WINEPATH_BIN:-$(command -v winepath 2>/dev/null || true)}"
    WINECFG_BIN="${WINECFG_BIN:-$(command -v winecfg 2>/dev/null || true)}"
fi


# Resolve a versioned Autodesk component directory from the offline Windows tree.
# The Windows VM mount exposes NTFS junctions such as "Current" as /sysroot/...
# symlinks, which are intentionally ignored here. We select real numeric version
# directories instead. Set the corresponding inventor.env value to a specific
# version to override auto-detection.
detect_versioned_component() {
    local base="$1"
    local requested="${2:-auto}"
    local version

    if [[ -n "$requested" && "$requested" != "auto" ]]; then
        [[ -d "$base/$requested" ]] || return 1
        printf '%s\n' "$requested"
        return 0
    fi

    version="$(
        find "$base" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null \
            | grep -E '^[0-9]+(\.[0-9]+)+$' \
            | sort -V \
            | tail -n 1
    )"
    [[ -n "$version" ]] || return 1
    printf '%s\n' "$version"
}

detect_adsk_identity_version() {
    detect_versioned_component \
        "$WINDOWS_MOUNT/Program Files/Autodesk/AdskIdentityManager" \
        "${ADSK_IDENTITY_VERSION:-auto}"
}

detect_adsk_licensing_version() {
    detect_versioned_component \
        "$WINDOWS_MOUNT/Program Files (x86)/Common Files/Autodesk Shared/AdskLicensing" \
        "${ADSK_LICENSING_VERSION:-auto}"
}

require_command() {
    local cmd="$1"
    local hint="${2:-}"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: Required command not found: $cmd" >&2
        [[ -n "$hint" ]] && echo "       $hint" >&2
        return 1
    fi
}

require_wine() {
    if [[ -z "$WINE_BIN" || ! -x "$WINE_BIN" ]]; then
        echo "ERROR: Wine is not installed. Run: bash scripts/phase0-setup.sh" >&2
        return 1
    fi
    local actual
    actual="$($WINE_BIN --version 2>/dev/null || true)"
    if [[ "$actual" != wine-${WINE_VERSION}* ]]; then
        echo "ERROR: This project is pinned to Wine $WINE_VERSION; found '${actual:-unknown}'." >&2
        echo "       Run scripts/phase0-setup.sh or set WINE_BIN to a Wine $WINE_VERSION installation." >&2
        return 1
    fi
}

detect_windows_user() {
    if [[ -n "${WINDOWS_USER:-}" ]]; then
        printf '%s\n' "$WINDOWS_USER"
        return 0
    fi
    if [[ ! -d "$WINDOWS_MOUNT/Users" ]]; then
        return 1
    fi
    find "$WINDOWS_MOUNT/Users" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null \
        | grep -vxE 'Public|Default|Default User|All Users|defaultuser0|WDAGUtilityAccount' \
        | head -n 1
}

# Populate GUI environment variables from explicit config, the current shell,
# or a GNOME session owned by the same user. This makes plain SSH launches work
# when the same account already owns a local GNOME/Xorg session.
detect_graphical_session() {
    [[ -n "${INVENTOR_DISPLAY:-}" ]] && export DISPLAY="$INVENTOR_DISPLAY"
    [[ -n "${INVENTOR_XAUTHORITY:-}" ]] && export XAUTHORITY="$INVENTOR_XAUTHORITY"
    [[ -n "${INVENTOR_DBUS_SESSION_BUS_ADDRESS:-}" ]] && export DBUS_SESSION_BUS_ADDRESS="$INVENTOR_DBUS_SESSION_BUS_ADDRESS"
    [[ -n "${INVENTOR_XDG_RUNTIME_DIR:-}" ]] && export XDG_RUNTIME_DIR="$INVENTOR_XDG_RUNTIME_DIR"

    [[ -n "${DISPLAY:-}" ]] && return 0

    local pid key value
    pid="$(pgrep -u "$(id -u)" -x gnome-shell 2>/dev/null | head -n 1 || true)"
    [[ -z "$pid" || ! -r "/proc/$pid/environ" ]] && return 1

    while IFS='=' read -r key value; do
        case "$key" in
            DISPLAY) export DISPLAY="$value" ;;
            XAUTHORITY) export XAUTHORITY="$value" ;;
            DBUS_SESSION_BUS_ADDRESS) export DBUS_SESSION_BUS_ADDRESS="$value" ;;
            XDG_RUNTIME_DIR) export XDG_RUNTIME_DIR="$value" ;;
        esac
    done < <(tr '\0' '\n' < "/proc/$pid/environ" | grep -E '^(DISPLAY|XAUTHORITY|DBUS_SESSION_BUS_ADDRESS|XDG_RUNTIME_DIR)=')

    [[ -n "${DISPLAY:-}" ]]
}

normalize_gpu_uuid() {
    local uuid="${DXVK_FILTER_DEVICE_UUID:-}"
    uuid="${uuid//-/}"
    if [[ -n "$uuid" && ! "$uuid" =~ ^[0-9A-Fa-f]{32}$ ]]; then
        echo "ERROR: DXVK_FILTER_DEVICE_UUID must be 32 hexadecimal characters (dashes are allowed in inventor.env)." >&2
        return 1
    fi
    if [[ -n "$uuid" ]]; then
        export DXVK_FILTER_DEVICE_UUID="${uuid,,}"
    fi
}
