# Autodesk Inventor 2026 COM bridge for Ubuntu

Run Autodesk Inventor 2026 inside a Windows 11 KVM/libvirt virtual machine while Ubuntu applications use Inventor through an authenticated HTTP bridge. All Inventor COM calls stay local to Windows through `pywin32`; Linux applications never need COM or Autodesk runtimes.

## Architecture

```text
Ubuntu host / Rishika
        |
        | HTTP + API token
        v
Windows 11 VM (inventor-win11)
        |
        | serialized pywin32 COM worker
        v
Inventor.Application
```

## Start here

For a new Ubuntu server, follow **[`docs/SETUP.md`](docs/SETUP.md)**. It covers the complete setup from KVM/libvirt installation through Windows 11, Inventor, the Windows bridge, fixed VM-IP configuration, Rishika, startup/shutdown and troubleshooting.

## Exact first-time installation order

1. Extract this repository on Ubuntu.
2. Run `bash scripts/linux/setup-host.sh`.
3. Log out and back in.
4. Download an official Windows 11 x64 ISO.
5. Copy `windows-vm.env.example` to `windows-vm.env` and configure it.
6. Run `bash scripts/linux/create-windows-vm.sh`.
7. Connect to the loopback-only VNC console through an SSH tunnel and install Windows 11.
8. Complete Windows Update.
9. Install Python 3.11+ x64 in Windows.
10. Install Autodesk Inventor 2026 in Windows.
11. Launch Inventor manually and complete Autodesk sign-in/licensing and first-run dialogs.
12. Copy `dist/windows-bridge.zip` into Windows and extract it to `C:\InventorVmBridge`.
13. In Administrator PowerShell run `Set-ExecutionPolicy -Scope Process Bypass`, then `./install.ps1`.
14. In Windows run `./test_bridge.ps1` and confirm `inventor_connected: true`.
15. On Ubuntu set `VM_IP` in `.bridge-client.env` to the Windows VM IPv4 address. Use `bash scripts/linux/set-vm-ip.sh` to save the current libvirt DHCP lease automatically, or pass the IPv4 explicitly.
16. On Ubuntu run `bash scripts/linux/bridge-health.sh`.
17. Extract/configure Rishika and run `bash scripts/linux/configure-rishika.sh /path/to/Rishika`.
18. In Rishika run `python3 src/preflight.py --phase windows` and an actual CAD bridge test.
19. Start Rishika normally.

The Windows user that owns the Autodesk session must remain logged in. Inventor may be minimized and the remote desktop/VNC viewer may be disconnected.

## Why `VM_IP` is explicit

`.bridge-client.env` is the authoritative Ubuntu-side bridge target. Keeping an explicit `VM_IP` avoids depending on `qemu-guest-agent` or a particular libvirt address-discovery source.

For this prepared deployment, the supplied hidden `.bridge-client.env` contains the currently confirmed address:

```dotenv
VM_NAME="inventor-win11"
VM_IP="192.168.122.123"
INVENTOR_BRIDGE_PORT="8765"
INVENTOR_BRIDGE_TOKEN="<private token>"
```

If the VM is recreated or its DHCP lease changes, refresh it with:

```bash
bash scripts/linux/set-vm-ip.sh
```

or:

```bash
bash scripts/linux/set-vm-ip.sh 192.168.122.123
```

You can verify the current lease manually with:

```bash
virsh --connect qemu:///system domifaddr inventor-win11 --source lease
```

## Repository layout

```text
README.md
windows-vm.env.example
.bridge-client.env.example
docs/
  SETUP.md
scripts/linux/
  common-vm.sh
  setup-host.sh
  create-windows-vm.sh
  start-windows-vm.sh
  stop-windows-vm.sh
  set-vm-ip.sh
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
cd /path/to/inventor-on-linux-ubuntu
bash scripts/linux/start-windows-vm.sh
```

Sign in to the configured Windows user. The **Inventor VM Bridge** Scheduled Task starts at logon. Then verify from Ubuntu:

```bash
bash scripts/linux/vm-ip.sh
bash scripts/linux/bridge-health.sh
```

Start Rishika:

```bash
cd /path/to/Rishika
./search_app.sh
```

## Bridge API

- `GET /health` — process/worker health.
- `GET /v1/status` — authenticated Inventor/COM status.
- `POST /v1/extract` — authenticated CAD extraction for IPT/IAM/STEP/STP/ZIP.

Extraction returns a ZIP containing `metadata.json`, `model.stl`, `model.step`, and `bridge.json`. For assemblies with external references, upload a ZIP containing the root `.iam` and referenced `.ipt` files with relative paths preserved.

## Configuration and secrets

- `windows-vm.env` — local VM sizing and ISO path; gitignored.
- `.bridge-client.env` — Ubuntu bridge target (`VM_IP`), port and API token; gitignored and hidden.
- `windows_bridge/.env` — Windows bridge runtime settings/token; gitignored.
- Rishika `.env` — application-side bridge settings; private.

The Windows and Ubuntu bridge tokens must match exactly. Do not post or commit the token.

## Administration

Ubuntu:

```bash
bash scripts/linux/doctor.sh
bash scripts/linux/set-vm-ip.sh
bash scripts/linux/vm-ip.sh
bash scripts/linux/bridge-health.sh
bash scripts/linux/stop-windows-vm.sh
```

Windows (`C:\InventorVmBridge`):

```powershell
./start_bridge.ps1
./stop_bridge.ps1
./test_bridge.ps1
```

See [`docs/SETUP.md`](docs/SETUP.md) for the full procedure.
