#!/usr/bin/env bash
# Non-destructive preflight report for the Ubuntu port.
set -u
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

failures=0
warnings=0
ok()   { printf 'OK   %s\n' "$*"; }
warn() { printf 'WARN %s\n' "$*"; warnings=$((warnings+1)); }
fail() { printf 'FAIL %s\n' "$*"; failures=$((failures+1)); }

printf '=== Inventor on Linux doctor ===\n'
printf 'Project: %s\n\n' "$PROJECT_DIR"

if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    if [[ "${ID:-}" == ubuntu && "${VERSION_ID:-}" == 22.04 ]]; then ok "OS: ${PRETTY_NAME:-Ubuntu 22.04}"; else fail "Expected Ubuntu 22.04; found ${PRETTY_NAME:-unknown}"; fi
else fail "/etc/os-release unavailable"; fi

[[ "$(uname -m)" == x86_64 ]] && ok "Architecture: x86_64" || fail "Architecture: $(uname -m) (x86_64 required)"
kmajor="$(uname -r | cut -d. -f1)"; (( kmajor >= 6 )) && ok "Kernel: $(uname -r)" || fail "Kernel 6.x+ required; found $(uname -r)"

if require_wine >/dev/null 2>&1; then ok "Wine: $($WINE_BIN --version) ($WINE_BIN)"; else fail "Wine $WINE_VERSION not detected"; fi
[[ -f "$DXVK_DIR/x64/d3d11.dll" && -f "$DXVK_DIR/x64/dxgi.dll" ]] && ok "DXVK $DXVK_VERSION: $DXVK_DIR" || fail "DXVK $DXVK_VERSION missing at $DXVK_DIR"
[[ -s "$WEBVIEW2_INSTALLER" ]] && ok "WebView2 installer: $WEBVIEW2_INSTALLER" || fail "WebView2 installer missing; run phase0-setup.sh"
command -v hivexregedit >/dev/null 2>&1 && ok "hivexregedit available" || fail "hivexregedit missing"
command -v winetricks >/dev/null 2>&1 && ok "winetricks available" || fail "winetricks missing"
if command -v xdg-settings >/dev/null 2>&1; then
    browser="$(xdg-settings get default-web-browser 2>/dev/null || true)"
    [[ -n "$browser" ]] && ok "Default desktop browser: $browser" || warn "No default desktop browser detected; first Autodesk SSO login requires one"
else
    warn "xdg-settings unavailable; cannot verify the browser required for first Autodesk SSO login"
fi

if command -v vulkaninfo >/dev/null 2>&1 && vulkaninfo --summary >/tmp/inventor-doctor-vulkan.txt 2>&1; then
    gpu_count="$(grep -c '^GPU[0-9]\+:' /tmp/inventor-doctor-vulkan.txt || true)"
    ok "Vulkan works; $gpu_count device(s) enumerated"
else
    fail "Vulkan validation failed (run vulkaninfo --summary)"
fi

if [[ -d "$WINDOWS_MOUNT/Windows" ]]; then
    ok "Windows source mounted: $WINDOWS_MOUNT"
    [[ -d "$WINDOWS_MOUNT/Program Files/Autodesk/Inventor 2026" ]] && ok "Inventor 2026 source found" || fail "Inventor 2026 not found under Windows Program Files"

    identity_version="$(detect_adsk_identity_version 2>/dev/null || true)"
    if [[ -n "$identity_version" ]]; then
        ok "Autodesk Identity Manager $identity_version source found"
    else
        fail "Autodesk Identity Manager version directory not found (configured: ${ADSK_IDENTITY_VERSION:-auto})"
    fi

    licensing_version="$(detect_adsk_licensing_version 2>/dev/null || true)"
    if [[ -n "$licensing_version" ]]; then
        ok "Autodesk Licensing $licensing_version source found"
    else
        fail "Autodesk Licensing version directory not found (configured: ${ADSK_LICENSING_VERSION:-auto})"
    fi
else
    fail "Windows source is not mounted at $WINDOWS_MOUNT (Linux-only server: see docs/windows-vm.md)"
fi

if [[ -f "$PROJECT_DIR/registry/autodesk-full.reg" ]]; then ok "Autodesk registry export exists"; else warn "registry/autodesk-full.reg not created yet; run export-registry.sh"; fi

if detect_graphical_session; then
    ok "Graphical display: DISPLAY=$DISPLAY"
else
    warn "No DISPLAY in this shell and no same-user GNOME session auto-detected. Configure INVENTOR_DISPLAY/XAUTHORITY for server launches."
fi

if normalize_gpu_uuid; then
    if [[ -n "${DXVK_FILTER_DEVICE_UUID:-}" ]]; then ok "DXVK GPU pin: $DXVK_FILTER_DEVICE_UUID"; else warn "No DXVK GPU UUID configured; DXVK will choose the first matching Vulkan GPU"; fi
else
    fail "Invalid DXVK_FILTER_DEVICE_UUID"
fi

printf '\nResult: %d failure(s), %d warning(s)\n' "$failures" "$warnings"
(( failures == 0 ))
