#!/usr/bin/env bash
# Register the Autodesk OAuth callback handler and an optional desktop entry.
set -euo pipefail
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

if [[ $EUID -eq 0 ]]; then
    echo "ERROR: Run this as the Linux user who will launch Inventor, not root." >&2
    exit 1
fi

mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications" \
    "$HOME/.local/share/icons/hicolor/256x256/apps" "$LOGDIR"

ln -sfn "$PROJECT_DIR/scripts/adskidmgr-callback.sh" "$HOME/.local/bin/adskidmgr-callback"
ln -sfn "$PROJECT_DIR/scripts/launch-inventor.sh" "$HOME/.local/bin/launch-inventor"
chmod +x "$PROJECT_DIR/scripts/adskidmgr-callback.sh" "$PROJECT_DIR/scripts/launch-inventor.sh"

cat > "$HOME/.local/share/applications/adskidmgr-handler.desktop" <<EOF2
[Desktop Entry]
Type=Application
Name=Autodesk Identity Manager
Exec=$HOME/.local/bin/adskidmgr-callback %u
MimeType=x-scheme-handler/adskidmgr;
NoDisplay=true
Terminal=false
EOF2

xdg-mime default adskidmgr-handler.desktop x-scheme-handler/adskidmgr

icon_path="$HOME/.local/share/icons/hicolor/256x256/apps/autodesk-inventor-2026.png"
source_icon="$WINEPREFIX/drive_c/Program Files/Autodesk/Inventor 2026/Bin/idv.ico"
if [[ -f "$source_icon" ]] && command -v convert >/dev/null 2>&1; then
    convert "${source_icon}[0]" -thumbnail 256x256 -flatten "$icon_path" 2>/dev/null || true
fi

cat > "$HOME/.local/share/applications/autodesk-inventor-2026.desktop" <<EOF2
[Desktop Entry]
Type=Application
Name=Autodesk Inventor 2026
GenericName=CAD Application
Comment=Autodesk Inventor Professional 2026 under Wine
Exec=$HOME/.local/bin/launch-inventor
Icon=autodesk-inventor-2026
Terminal=false
Categories=Graphics;Engineering;3DGraphics;
StartupWMClass=inventor.exe
Keywords=CAD;3D;Modeling;Engineering;Inventor;Autodesk;
EOF2

update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true

echo "User integration installed."
echo "OAuth handler: $(xdg-mime query default x-scheme-handler/adskidmgr 2>/dev/null || echo unknown)"
echo "Launcher:      $HOME/.local/bin/launch-inventor"
