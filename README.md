# Autodesk Inventor 2026 on an Ubuntu server — Windows VM COM bridge

This repository replaces the previous Wine-based approach. Autodesk Inventor remains installed and licensed inside the existing Windows 11 libvirt/KVM VM, while Ubuntu applications call a small authenticated HTTP bridge inside that VM.

## Architecture

```text
Ubuntu host / Rishika
        |
        | HTTP + API token
        v
Windows 11 VM (inventor-win11)
        |
        | one serialized COM worker thread
        v
Inventor.Application
        |
        +--> metadata.json
        +--> model.stl
        +--> model.step
```

Linux never instantiates COM and Inventor never needs Wine. The Windows bridge keeps all Autodesk licensing, Identity Manager, WebView2, graphics and COM behavior on the supported Windows installation.

## What is in this repository

- `windows_bridge/` — FastAPI server and serialized Inventor COM worker, installed inside the Windows VM.
- `dist/windows-bridge.zip` — transfer-ready copy of `windows_bridge/` for the VM.
- `scripts/linux/vm-ip.sh` — discovers the VM IPv4 address through libvirt.
- `scripts/linux/start-windows-vm.sh` — starts the existing `inventor-win11` domain.
- `scripts/linux/bridge-health.sh` — verifies Ubuntu -> VM -> Inventor COM end-to-end.
- `scripts/linux/configure-rishika.sh` — writes matching bridge settings into an extracted Rishika directory.
- `.bridge-client.env` — generated local API token/configuration. It is gitignored.

## 1. Replace the old repository on Ubuntu

Extract this archive where the old `inventor-on-linux-ubuntu` repository lived. If your libvirt domain is not named `inventor-win11`, create `windows-vm.env` from the example and change `VM_NAME`.

```bash
cp windows-vm.env.example windows-vm.env
nano windows-vm.env
```

The supplied `.bridge-client.env` contains a generated token that matches the supplied `windows_bridge/.env`. Both files are intentionally excluded by `.gitignore`.

## 2. Start the existing Windows VM

```bash
bash scripts/linux/start-windows-vm.sh
```

If automatic address discovery works, this also prints the VM IPv4 address. If not, run `ipconfig` in Windows and set `VM_IP` in `windows-vm.env`.

## 3. Install the bridge inside Windows

Transfer `dist/windows-bridge.zip` into the Windows VM, for example through the existing VNC/RDP session or another file-transfer method. Extract it to a persistent location such as:

```text
C:\InventorVmBridge
```

Open **PowerShell as Administrator** in that directory and run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\install.ps1
```

The installer:

1. creates a local Python virtual environment;
2. installs FastAPI, pywin32 and bridge dependencies;
3. creates an inbound Windows Firewall rule for TCP 8765;
4. registers `Inventor VM Bridge` as an **interactive-user logon task**, not a Windows service;
5. starts the bridge;
6. tests local bridge -> Inventor COM connectivity.

### Important Windows session requirement

The bridge intentionally runs in the logged-in desktop session because Inventor is an interactive desktop application. Keep the Autodesk-licensed Windows user logged in. The session may be locked/disconnected, but do not run the bridge as a Session 0 Windows service.

Launch Inventor manually once after installation if Autodesk requires sign-in or first-run dialogs. After that, the bridge can attach to the existing process or start Inventor automatically.

## 4. Verify from Ubuntu

```bash
bash scripts/linux/bridge-health.sh
```

Expected shape of the result:

```json
{"status":"ready","worker_alive":true}
{"inventor_connected":true,"inventor_version":"..."}
```

This test proves the complete path:

```text
Ubuntu -> VM TCP -> authenticated bridge -> pywin32 -> Inventor.Application
```

## 5. Connect Rishika

The companion replacement `Rishika.zip` already contains the same generated bridge token and defaults to:

```dotenv
INVENTOR_BACKEND=remote
INVENTOR_BRIDGE_URL=auto
INVENTOR_VM_NAME=inventor-win11
INVENTOR_BRIDGE_PORT=8765
```

If you extract a different Rishika copy, synchronize its bridge settings with:

```bash
bash scripts/linux/configure-rishika.sh /path/to/Rishika
```

`INVENTOR_BRIDGE_URL=auto` is designed for Rishika running directly on the same Ubuntu/libvirt host. If Rishika runs inside Docker or on another machine, set an explicit URL instead:

```dotenv
INVENTOR_BRIDGE_URL=http://<windows-vm-ip>:8765
```

## API

### Health

```text
GET /health
```

Does not require authentication and only reports bridge process health.

### Inventor status

```text
GET /v1/status
X-Inventor-Bridge-Token: <token>
```

Attaches to or starts `Inventor.Application` and returns basic status.

### Extract CAD

```text
POST /v1/extract
X-Inventor-Bridge-Token: <token>
Content-Type: multipart/form-data
file=<IPT/IAM/STEP/STP/ZIP>
```

Returns a ZIP containing:

```text
metadata.json
model.stl
model.step
bridge.json
```

For an assembly with external references, upload a ZIP containing the root `.iam` plus all referenced `.ipt` files with relative paths preserved. The bridge safely extracts the bundle in Windows and opens the most likely root assembly.

## Concurrency model

FastAPI may accept multiple network requests, but all Inventor operations are placed on one dedicated COM STA thread. This prevents concurrent arbitrary request threads from touching the same Inventor automation object. Requests are therefore serialized at the Inventor boundary.

## Security model

- `/v1/*` requires a long random `X-Inventor-Bridge-Token`.
- The generated token lives only in gitignored `.env` files.
- Do not expose TCP 8765 to the public internet.
- The Windows firewall rule is for the VM NIC; use libvirt/NAT or your LAN firewall to keep it private.
- Uploaded CAD files are stored only in per-request temporary directories and removed after the response is sent.
- ZIP extraction rejects path traversal entries.

## Bridge administration in Windows

```powershell
.\test_bridge.ps1
.\stop_bridge.ps1
.\start_bridge.ps1
```

Logs are written under:

```text
windows_bridge\logs\
```

Stopping the bridge leaves Inventor running by default. Set `INVENTOR_QUIT_ON_BRIDGE_EXIT=true` only if you explicitly want the bridge to close an Inventor process that it started.

## Why the Wine files were removed

The previous repository existed to reproduce enough Windows behavior under Wine to start Inventor. That is no longer needed for this architecture. The VM remains the Inventor execution environment; Ubuntu is now the orchestration and application environment.
