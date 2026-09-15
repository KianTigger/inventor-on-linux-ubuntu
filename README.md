# Autodesk Inventor 2026 COM bridge for Ubuntu

Run Autodesk Inventor 2026 inside a Windows 11 KVM/libvirt virtual machine while Ubuntu applications use Inventor through a small authenticated network bridge. All Inventor COM calls execute locally inside Windows through `pywin32`; Linux applications communicate with the bridge over HTTP.

## Architecture

```text
Ubuntu host / Rishika
        |
        | HTTP + API token
        v
Windows 11 VM (default: inventor-win11)
        |
        | serialized pywin32 COM worker
        v
Inventor.Application
        |
        +--> metadata.json
        +--> model.stl
        +--> model.step
```

## Start here

For a **new Ubuntu server with no Windows VM**, follow:

**[`docs/SETUP.md`](docs/SETUP.md)**

It contains the complete installation from KVM/libvirt prerequisites through Windows 11 installation, Inventor installation/licensing, bridge installation, Rishika configuration, normal startup order, shutdown and troubleshooting.

### Exact first-time installation order

1. Extract this repository on Ubuntu.
2. Run `bash scripts/linux/setup-host.sh`.
3. Log out and back in.
4. Download an official Windows 11 x64 ISO.
5. Copy `windows-vm.env.example` to `windows-vm.env` and configure it.
6. Run `bash scripts/linux/create-windows-vm.sh`.
7. Connect to the VM's VNC console through an SSH tunnel and install Windows 11.
8. Complete Windows Update.
9. Install Python 3.11+ x64 in Windows.
10. Install Autodesk Inventor 2026 in Windows.
11. Launch Inventor manually and complete Autodesk sign-in/licensing and first-run dialogs.
12. Copy `dist/windows-bridge.zip` into Windows and extract it to `C:\InventorVmBridge`.
13. In Administrator PowerShell run `Set-ExecutionPolicy -Scope Process Bypass`, then `.\install.ps1`.
14. In Windows run `.\test_bridge.ps1`.
15. On Ubuntu run `bash scripts/linux/bridge-health.sh`.
16. Extract/configure the supplied Rishika package.
17. In Rishika run `python3 src/preflight.py --phase windows` and an actual CAD bridge test.
18. Start Rishika normally.

Do not skip the manual Inventor launch/sign-in before relying on unattended bridge startup.

## Repository layout

```text
README.md
windows-vm.env.example
docs/
  SETUP.md
scripts/linux/
  common-vm.sh
  setup-host.sh
  create-windows-vm.sh
  start-windows-vm.sh
  stop-windows-vm.sh
  vm-ip.sh
  doctor.sh
  bridge-health.sh
  configure-rishika.sh
windows_bridge/
  install.ps1
  start_bridge.ps1
  stop_bridge.ps1
  test_bridge.ps1
  server.py
  inventor_worker.py
  ...
dist/
  windows-bridge.zip
```

## Normal startup after installation

On Ubuntu:

```bash
bash scripts/linux/start-windows-vm.sh
```

Sign in to the configured Windows desktop user. The **Inventor VM Bridge** Scheduled Task starts at logon. Then verify from Ubuntu:

```bash
bash scripts/linux/bridge-health.sh
```

Start Rishika:

```bash
cd /path/to/Rishika
./search_app.sh
```

The VNC console does not need to stay connected for normal automation. The Windows user session does need to remain logged in.

## Bridge API

### Process health

```text
GET /health
```

### Inventor/COM status

```text
GET /v1/status
X-Inventor-Bridge-Token: <token>
```

### Extract CAD metadata and geometry

```text
POST /v1/extract
X-Inventor-Bridge-Token: <token>
Content-Type: multipart/form-data
file=<IPT/IAM/STEP/STP/ZIP>
```

The response ZIP contains:

```text
metadata.json
model.stl
model.step
bridge.json
```

For an assembly with external references, upload a ZIP containing the root `.iam` and all referenced `.ipt` files with relative paths preserved.

## Concurrency

Network requests may arrive concurrently, but all Inventor work is serialized onto one dedicated COM STA worker thread. Arbitrary HTTP worker threads never operate on the Inventor COM object directly.

## Configuration and secrets

- `windows-vm.env` — local VM sizing, ISO path, optional fixed IP; gitignored.
- `.bridge-client.env` — Ubuntu bridge token/client settings; gitignored.
- `windows_bridge/.env` — Windows bridge token/runtime settings; gitignored.
- Rishika `.env` — application-side bridge settings; should remain private.

The supplied package contains matching bridge/client tokens so the two supplied archives work together. If you generate/rotate a token, update both Windows and Rishika/Ubuntu configurations.

## Administration

Ubuntu:

```bash
bash scripts/linux/doctor.sh
bash scripts/linux/vm-ip.sh
bash scripts/linux/bridge-health.sh
bash scripts/linux/stop-windows-vm.sh
```

Windows (`C:\InventorVmBridge`):

```powershell
.\start_bridge.ps1
.\stop_bridge.ps1
.\test_bridge.ps1
```

See [`docs/SETUP.md`](docs/SETUP.md) for detailed troubleshooting and security guidance.
