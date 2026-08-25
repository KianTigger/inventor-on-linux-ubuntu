#!/usr/bin/env bash
# Rebuild the Inventor 2026 Wine prefix from an existing Windows installation.
# WARNING: this deletes the configured WINEPREFIX.

set -euo pipefail
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"
require_wine
require_command winetricks "Run scripts/phase0-setup.sh"
require_command rsync "Run scripts/phase0-setup.sh"

FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

step_no=0
step() { step_no=$((step_no+1)); printf '\n[%02d] %s\n' "$step_no" "$*"; }

if [[ $EUID -eq 0 ]]; then
    echo "ERROR: Run this script as the Linux user who will run Inventor, not root." >&2
    exit 1
fi

# Preflight source tree before deleting an existing prefix.
required_paths=(
    "$WINDOWS_MOUNT/Windows/System32"
    "$WINDOWS_MOUNT/Program Files/Autodesk/Inventor 2026/Bin"
    "$WINDOWS_MOUNT/Program Files/Autodesk/Inventor 2026/Configuration"
    "$WINDOWS_MOUNT/Program Files/Autodesk/Inventor 2026/Preferences"
    "$WINDOWS_MOUNT/Program Files/Common Files/Autodesk Shared/Components/2026/1.8.0"
    "$WINDOWS_MOUNT/Program Files/Common Files/Autodesk Shared/RealDWG Shared 2026"
    "$WINDOWS_MOUNT/Program Files/Autodesk/AdskIdentityManager/Current"
    "$WINDOWS_MOUNT/Program Files (x86)/Common Files/Autodesk Shared/AdskLicensing/$ADSK_LICENSING_VERSION"
)
for path in "${required_paths[@]}"; do
    if [[ ! -e "$path" ]]; then
        echo "ERROR: Required Windows source path is missing:" >&2
        echo "       $path" >&2
        echo "       Check WINDOWS_MOUNT and the Autodesk component versions in inventor.env." >&2
        exit 1
    fi
done

WIN_USER="$(detect_windows_user || true)"
if [[ -z "$WIN_USER" ]]; then
    echo "ERROR: Could not detect a Windows user profile. Set WINDOWS_USER in inventor.env." >&2
    exit 1
fi

REGISTRY_FILE="$PROJECT_DIR/registry/autodesk-full.reg"
if [[ ! -f "$REGISTRY_FILE" && "${SKIP_REGISTRY_IMPORT:-0}" != 1 ]]; then
    echo "ERROR: $REGISTRY_FILE is missing." >&2
    echo "       Run: bash scripts/export-registry.sh" >&2
    echo "       To deliberately continue with only the script's minimal registry keys, set SKIP_REGISTRY_IMPORT=1." >&2
    exit 1
fi

[[ -f "$DXVK_DIR/x64/d3d11.dll" ]] || { echo "ERROR: DXVK missing at $DXVK_DIR; run phase0-setup.sh" >&2; exit 1; }
[[ -s "$WEBVIEW2_INSTALLER" ]] || { echo "ERROR: WebView2 installer missing at $WEBVIEW2_INSTALLER; run phase0-setup.sh" >&2; exit 1; }

if [[ -d "$WINEPREFIX" ]]; then
    echo "WARNING: This will permanently delete the existing Wine prefix:"
    echo "         $WINEPREFIX"
    if (( FORCE == 0 )); then
        if [[ -t 0 ]]; then
            read -r -p "Type REBUILD to continue: " answer
            [[ "$answer" == REBUILD ]] || { echo "Aborted."; exit 1; }
        else
            echo "ERROR: Non-interactive rebuild requires --force." >&2
            exit 1
        fi
    fi
fi

mkdir -p "$LOGDIR"
WEBVIEW2_LOG="$LOGDIR/webview2-install.log"

echo "=== Rebuilding Inventor 2026 Wine prefix ==="
echo "Wine:          $($WINE_BIN --version)"
echo "Windows source: $WINDOWS_MOUNT"
echo "Windows user:   $WIN_USER"
echo "Wine prefix:    $WINEPREFIX"

step "Stopping Wine and creating a clean 64-bit prefix"
"$WINESERVER_BIN" -k >/dev/null 2>&1 || true
sleep 2
rm -rf "$WINEPREFIX"
"$WINEBOOT_BIN" --init >/dev/null 2>&1
sleep 3

step "Setting Windows 10 compatibility mode"
PATH="$(dirname "$WINE_BIN"):$PATH" WINE="$WINE_BIN" WINESERVER="$WINESERVER_BIN" \
    WINEPREFIX="$WINEPREFIX" winetricks -q win10

step "Installing upstream DXVK $DXVK_VERSION"
bash "$SCRIPT_DIR/install-dxvk-prefix.sh"

DEST="$WINEPREFIX/drive_c/Program Files/Autodesk/Inventor 2026"
step "Copying Inventor 2026 binaries and configuration"
mkdir -p "$DEST"
rsync -a --exclude='Anark' "$WINDOWS_MOUNT/Program Files/Autodesk/Inventor 2026/Bin/" "$DEST/Bin/"
cp -a "$WINDOWS_MOUNT/Program Files/Autodesk/Inventor 2026/Configuration" "$DEST/"
cp -a "$WINDOWS_MOUNT/Program Files/Autodesk/Inventor 2026/Preferences" "$DEST/"

step "Copying Autodesk Shared Components"
for dll in "$WINDOWS_MOUNT/Program Files/Common Files/Autodesk Shared/Components/2026/1.8.0/"*.dll; do
    base="$(basename "$dll")"
    [[ -f "$DEST/Bin/$base" ]] || cp "$dll" "$DEST/Bin/"
done
mkdir -p "$WINEPREFIX/drive_c/Program Files/Common Files/Autodesk Shared"
cp -a "$WINDOWS_MOUNT/Program Files/Common Files/Autodesk Shared/Components" \
    "$WINEPREFIX/drive_c/Program Files/Common Files/Autodesk Shared/"

step "Copying MSVC/MFC runtime DLLs"
for dll in msvcp140.dll msvcp140_1.dll msvcp140_2.dll vcruntime140.dll vcruntime140_1.dll \
           concrt140.dll vcomp140.dll mfc140u.dll mfc140.dll; do
    if [[ -f "$WINDOWS_MOUNT/Windows/System32/$dll" ]]; then
        cp "$WINDOWS_MOUNT/Windows/System32/$dll" "$WINEPREFIX/drive_c/windows/system32/"
    else
        echo "  WARNING: Missing optional runtime DLL: $dll"
    fi
done

step "Copying RealDWG"
mkdir -p "$WINEPREFIX/drive_c/Program Files/Common Files/Autodesk Shared/RealDWG Shared 2026"
cp -a "$WINDOWS_MOUNT/Program Files/Common Files/Autodesk Shared/RealDWG Shared 2026/." \
    "$WINEPREFIX/drive_c/Program Files/Common Files/Autodesk Shared/RealDWG Shared 2026/"

step "Copying per-user RealDWG settings when available"
mkdir -p "$WINEPREFIX/drive_c/users/$USER/AppData/Roaming/Autodesk/Inventor 2026"
REALDWG_SETTINGS="$WINDOWS_MOUNT/Users/$WIN_USER/AppData/Roaming/Autodesk/Inventor 2026/RealDWGSettings.xml"
if [[ -f "$REALDWG_SETTINGS" ]]; then
    cp "$REALDWG_SETTINGS" "$WINEPREFIX/drive_c/users/$USER/AppData/Roaming/Autodesk/Inventor 2026/"
else
    echo "  NOTE: RealDWGSettings.xml not present for Windows user $WIN_USER"
fi

step "Starting Microsoft WebView2 Runtime installer"
"$WINE_BIN" "$WEBVIEW2_INSTALLER" /silent /install >"$WEBVIEW2_LOG" 2>&1 &
WEBVIEW_PID=$!
sleep 10

step "Copying Autodesk Identity Manager"
mkdir -p "$WINEPREFIX/drive_c/Program Files/Autodesk/AdskIdentityManager"
cp -a "$WINDOWS_MOUNT/Program Files/Autodesk/AdskIdentityManager/Current" \
    "$WINEPREFIX/drive_c/Program Files/Autodesk/AdskIdentityManager/"
# Tested Autodesk components look for these compatibility-version directories.
for version in 1.16.5.1 1.14.0.3; do
    rm -rf "$WINEPREFIX/drive_c/Program Files/Autodesk/AdskIdentityManager/$version"
    cp -a "$WINEPREFIX/drive_c/Program Files/Autodesk/AdskIdentityManager/Current" \
        "$WINEPREFIX/drive_c/Program Files/Autodesk/AdskIdentityManager/$version"
done

step "Copying Autodesk Licensing Service $ADSK_LICENSING_VERSION"
mkdir -p "$WINEPREFIX/drive_c/Program Files (x86)/Common Files/Autodesk Shared/AdskLicensing"
cp -a "$WINDOWS_MOUNT/Program Files (x86)/Common Files/Autodesk Shared/AdskLicensing/$ADSK_LICENSING_VERSION" \
    "$WINEPREFIX/drive_c/Program Files (x86)/Common Files/Autodesk Shared/AdskLicensing/"

step "Copying Autodesk license/cache files when available"
mkdir -p "$WINEPREFIX/drive_c/ProgramData/Autodesk/Adlm/ASR" \
         "$WINEPREFIX/drive_c/ProgramData/Autodesk/AdskLicensingService"
shopt -s nullglob
asr_files=("$WINDOWS_MOUNT/ProgramData/Autodesk/Adlm/ASR/INVPROSA202600F_"*.asr)
((${#asr_files[@]})) && cp "${asr_files[@]}" "$WINEPREFIX/drive_c/ProgramData/Autodesk/Adlm/ASR/"
for pair in \
    "$WINDOWS_MOUNT/ProgramData/Autodesk/Adlm/ProductInformation.pit|$WINEPREFIX/drive_c/ProgramData/Autodesk/Adlm/" \
    "$WINDOWS_MOUNT/ProgramData/Autodesk/AdskLicensingService/AdskLicensingService.data|$WINEPREFIX/drive_c/ProgramData/Autodesk/AdskLicensingService/" \
    "$WINDOWS_MOUNT/ProgramData/Autodesk/AdskLicensingService/AdskLicensingService.sds|$WINEPREFIX/drive_c/ProgramData/Autodesk/AdskLicensingService/"; do
    src="${pair%%|*}"; dst="${pair#*|}"
    [[ -f "$src" ]] && cp "$src" "$dst" || true
done
shopt -u nullglob

step "Importing Autodesk registry export"
if [[ -f "$REGISTRY_FILE" ]]; then
    REGISTRY_WIN="$($WINEPATH_BIN -w "$REGISTRY_FILE")"
    "$WINE_BIN" regedit /S "$REGISTRY_WIN"
else
    echo "  Registry import skipped by SKIP_REGISTRY_IMPORT=1"
fi

step "Applying required Inventor registry keys"
"$WINE_BIN" reg add 'HKLM\SOFTWARE\Autodesk\Inventor\RegistryVersion30.0' /v ProductVersionMajor /t REG_DWORD /d 30 /f >/dev/null
"$WINE_BIN" reg add 'HKLM\SOFTWARE\Autodesk\Inventor\RegistryVersion30.0' /v BinPath /t REG_SZ /d 'C:\Program Files\Autodesk\Inventor 2026\Bin\' /f >/dev/null
"$WINE_BIN" reg add 'HKLM\SOFTWARE\Autodesk\Inventor\RegistryVersion30.0' /v AppPath /t REG_SZ /d 'C:\Program Files\Autodesk\Inventor 2026\' /f >/dev/null
"$WINE_BIN" reg add 'HKLM\SOFTWARE\Autodesk\Inventor\RegistryVersion30.0' /v ClientVersion /t REG_SZ /d '30.0.17500.0000' /f >/dev/null
"$WINE_BIN" reg add 'HKLM\SOFTWARE\Autodesk\Inventor\RegistryVersion30.0' /v ProductEdition /t REG_SZ /d INVPROSA /f >/dev/null

step "Applying Autodesk Shared Components registry keys"
"$WINE_BIN" reg add 'HKLM\SOFTWARE\Autodesk\SharedComponents\2026' /v InstallPath /t REG_EXPAND_SZ /d 'C:\Program Files\Common Files\Autodesk Shared\Components\2026' /f >/dev/null
"$WINE_BIN" reg add 'HKLM\SOFTWARE\Autodesk\SharedComponents\2026' /v Version /t REG_EXPAND_SZ /d 1.8.0 /f >/dev/null

step "Applying Autodesk licensing/Identity Manager registry keys"
"$WINE_BIN" reg add 'HKLM\SOFTWARE\Autodesk\AdskLicensing' /v Version /t REG_EXPAND_SZ /d "$ADSK_LICENSING_VERSION" /f >/dev/null
for version in 1.16.5.1 1.14.0.3; do
    "$WINE_BIN" reg add "HKLM\\SOFTWARE\\Autodesk\\AdskIdentityManager\\$version" /v Location /t REG_EXPAND_SZ \
        /d "C:\\Program Files\\Autodesk\\AdskIdentityManager\\$version" /f >/dev/null
done

step "Registering the Windows-side adskidmgr protocol"
"$WINE_BIN" reg add 'HKCR\adskidmgr' /ve /t REG_SZ /d 'URL:Autodesk Identity Manager Protocol' /f >/dev/null
"$WINE_BIN" reg add 'HKCR\adskidmgr' /v 'URL Protocol' /t REG_SZ /d '' /f >/dev/null
"$WINE_BIN" reg add 'HKCR\adskidmgr\shell\open\command' /ve /t REG_SZ \
    /d '"C:\Program Files\Autodesk\AdskIdentityManager\Current\AdskIdentityManager.exe" "%1"' /f >/dev/null

step "Setting Wine Windows PATH"
"$WINE_BIN" reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' /v Path /t REG_EXPAND_SZ \
    /d 'C:\windows\system32;C:\windows;C:\windows\system32\wbem;C:\Program Files\Common Files\Autodesk Shared\Components\2026\1.8.0;C:\Program Files\Autodesk\Inventor 2026\Bin' /f >/dev/null

step "Installing IDSDK SSO plugin into the Licensing Agent"
AGENTDIR="$WINEPREFIX/drive_c/Program Files (x86)/Common Files/Autodesk Shared/AdskLicensing/$ADSK_LICENSING_VERSION/AdskLicensingAgent"
IDMGRDIR="$WINEPREFIX/drive_c/Program Files/Autodesk/AdskIdentityManager/Current"
mkdir -p "$AGENTDIR/SSOPlugin/Current"
cp "$IDMGRDIR/SSOPlugin/Current/"*.dll "$AGENTDIR/SSOPlugin/Current/"
cat > "$AGENTDIR/IDSDKVersionCompatibility.config" <<VEOF
{
    "comment": "Version compatibility file",
    "ssoClientPlugin": [
        {
            "version": "0",
            "module": "IdSDKPlugin.dll",
            "modulePath": "C:\\\\Program Files (x86)\\\\Common Files\\\\Autodesk Shared\\\\AdskLicensing\\\\$ADSK_LICENSING_VERSION\\\\AdskLicensingAgent\\\\SSOPlugin\\\\Current",
            "modulePathWoW64": "C:\\\\Program Files (x86)\\\\Common Files\\\\Autodesk Shared\\\\AdskLicensing\\\\$ADSK_LICENSING_VERSION\\\\AdskLicensingAgent\\\\SSOPlugin\\\\Current",
            "compatibleSsoServicesVersion": { "minVersion": "0.0" }
        }
    ]
}
VEOF

step "Disabling known non-essential or Wine-broken Inventor add-ins"
ADDINS="$DEST/Bin/Addins"
mkdir -p "$ADDINS/disabled/libs"
for file in Anark.Core.addin Autodesk.Feedback.Inventor.addin Autodesk.PerfFeedbackAddin.Inventor.addin \
            Autodesk.SharedViews.Inventor.addin Autodesk.InteractiveTutorial.Inventor.addin \
            Autodesk.Publisher.Inventor.addin autodesk.dynamicsimulation.inventor.addin \
            autodesk.frameanalysis.inventor.addin autodesk.simulationstressanalysis.inventor.addin \
            autodesk.translatorfusion.inventor.addin autodesk.ilogic.inventor.addin; do
    [[ -e "$ADDINS/$file" ]] && mv "$ADDINS/$file" "$ADDINS/disabled/"
done

step "Moving InteractiveTutorial DLLs that trigger Wine/Mono failures"
[[ -f "$DEST/Bin/InteractiveTutorial.dll" ]] && mv "$DEST/Bin/InteractiveTutorial.dll" "$ADDINS/disabled/libs/"
[[ -f "$DEST/Bin/en-US/InteractiveTutorial.resources.dll" ]] && mv "$DEST/Bin/en-US/InteractiveTutorial.resources.dll" "$ADDINS/disabled/libs/"

step "Disabling Autodesk CER crash reporter"
[[ -f "$DEST/Bin/CER/senddmp.exe" ]] && mv "$DEST/Bin/CER/senddmp.exe" "$DEST/Bin/CER/senddmp.exe.disabled"

step "Removing bcp47langs Wine stubs if present"
for file in "$WINEPREFIX/drive_c/windows/system32/bcp47langs.dll" "$WINEPREFIX/drive_c/windows/syswow64/bcp47langs.dll"; do
    [[ -f "$file" ]] && mv "$file" "$file.disabled"
done
"$WINE_BIN" reg delete 'HKCU\Software\Wine\DllOverrides' /v bcp47langs /f >/dev/null 2>&1 || true

step "Copying .NET runtime from Windows when available"
if [[ -d "$WINDOWS_MOUNT/Program Files/dotnet" ]]; then
    rm -rf "$WINEPREFIX/drive_c/Program Files/dotnet"
    cp -a "$WINDOWS_MOUNT/Program Files/dotnet" "$WINEPREFIX/drive_c/Program Files/"
else
    echo "  NOTE: Windows dotnet directory not found; continuing."
fi

PUBLIC_INV="$WINEPREFIX/drive_c/users/Public/Documents/Autodesk/Inventor 2026"
mkdir -p "$PUBLIC_INV"
step "Copying Design Data"
[[ -d "$WINDOWS_MOUNT/Users/Public/Documents/Autodesk/Inventor 2026/Design Data" ]] && \
    cp -a "$WINDOWS_MOUNT/Users/Public/Documents/Autodesk/Inventor 2026/Design Data" "$PUBLIC_INV/" || echo "  NOTE: Design Data not found"

step "Copying Templates"
if [[ -d "$WINDOWS_MOUNT/Users/Public/Documents/Autodesk/Inventor 2026/Templates" ]]; then
    cp -a "$WINDOWS_MOUNT/Users/Public/Documents/Autodesk/Inventor 2026/Templates" "$PUBLIC_INV/"
else
    echo "  NOTE: Templates not found"
fi

step "Copying Textures"
[[ -d "$WINDOWS_MOUNT/Users/Public/Documents/Autodesk/Inventor 2026/Textures" ]] && \
    cp -a "$WINDOWS_MOUNT/Users/Public/Documents/Autodesk/Inventor 2026/Textures" "$PUBLIC_INV/" || echo "  NOTE: Textures not found"

step "Applying the tested OGSFactory.dll null-pointer patch"
OGSDLL="$DEST/Bin/OGSFactory.dll"
if [[ ! -f "$OGSDLL" ]]; then
    echo "ERROR: OGSFactory.dll not found." >&2
    exit 1
fi
# The binary patch is build-specific. Refuse to write at fixed offsets if the
# first crash-site bytes do not match the tested Inventor 2026 binary.
site1="$(od -An -tx1 -N8 -j $((0x56E5B)) "$OGSDLL" | tr -d ' \n')"
if [[ "$site1" == e9009c0b00909090 ]]; then
    echo "  OGSFactory.dll already appears patched; skipping."
elif [[ "$site1" == 488b4c2470488b11 ]]; then
    [[ -f "$OGSDLL.original" ]] || cp -a "$OGSDLL" "$OGSDLL.original"
    printf '\xe9\x00\x9c\x0b\x00\x90\x90\x90' | dd of="$OGSDLL" bs=1 seek=$((0x56E5B)) conv=notrunc status=none
    printf '\x48\x8b\x4c\x24\x70\x48\x85\xc9\x0f\x84\x11\x64\xf4\xff\x48\x8b\x11\xe9\xed\x63\xf4\xff' | dd of="$OGSDLL" bs=1 seek=$((0x110A60)) conv=notrunc status=none
    printf '\xe9\xc9\x9b\x0b\x00\x90\x90\x90' | dd of="$OGSDLL" bs=1 seek=$((0x56EA8)) conv=notrunc status=none
    printf '\x48\x8b\x4c\x24\x70\x48\x85\xc9\x0f\x84\x48\x64\xf4\xff\x48\x8b\x11\xe9\x24\x64\xf4\xff' | dd of="$OGSDLL" bs=1 seek=$((0x110A76)) conv=notrunc status=none
    echo "  Patched; original saved as OGSFactory.dll.original"
else
    echo "ERROR: OGSFactory.dll does not match the tested Inventor 2026 build at patch offset 0x56E5B." >&2
    echo "       Found bytes: $site1" >&2
    echo "       Refusing to apply a fixed-offset binary patch to an unknown build." >&2
    exit 1
fi

step "Waiting for WebView2 installation"
if kill -0 "$WEBVIEW_PID" >/dev/null 2>&1; then
    wait "$WEBVIEW_PID" || echo "  WARNING: WebView2 installer returned a non-zero status; inspect $WEBVIEW2_LOG"
fi
sleep 2

step "Configuring optional D: drive mapping"
rm -f "$WINEPREFIX/dosdevices/d:" 2>/dev/null || true
if [[ -n "${DATA_DRIVE:-}" ]]; then
    if [[ -d "$DATA_DRIVE" ]]; then
        ln -s "$DATA_DRIVE" "$WINEPREFIX/dosdevices/d:"
        echo "  D: -> $DATA_DRIVE"
    else
        echo "  WARNING: DATA_DRIVE does not exist: $DATA_DRIVE"
    fi
else
    echo "  DATA_DRIVE is not configured; D: mapping skipped."
fi

"$WINESERVER_BIN" -k >/dev/null 2>&1 || true

echo
echo "=== Prefix rebuild complete ==="
echo "Prefix: $WINEPREFIX"
echo "Next:"
echo "  bash scripts/install-wbemprox-patch.sh"
echo "  bash scripts/setup-user-integration.sh"
echo "  bash scripts/doctor.sh"
echo "  bash scripts/launch-inventor.sh"
