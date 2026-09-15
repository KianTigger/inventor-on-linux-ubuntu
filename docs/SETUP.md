# Complete setup: Ubuntu + Windows 11 VM + Inventor 2026 + Rishika bridge

This guide starts from an Ubuntu server that does not yet have the Windows VM. It ends with Rishika on Ubuntu controlling Autodesk Inventor 2026 through the Inventor COM API inside Windows.

## Final architecture

```text
Rishika / Python on Ubuntu
        |
        | authenticated HTTP on the libvirt private network
        v
Inventor VM Bridge (Windows user session)
        |
        | local pywin32 / COM
        v
Autodesk Inventor 2026 on Windows 11
```

Inventor and Autodesk licensing remain entirely inside Windows. Ubuntu does not instantiate COM.

## Hardware and software expectations

The Ubuntu host must support hardware virtualization (Intel VT-x/AMD-V enabled in firmware). Windows 11 requires UEFI/Secure-Boot-capable firmware and TPM 2.0. The VM creation script uses OVMF UEFI and an emulated TPM 2.0.

For Inventor 2026, Autodesk recommends 32 GB RAM, a 3 GHz+ CPU with 4+ cores, and a DirectX-capable GPU. The repository defaults the VM to 32 GB RAM, 8 vCPUs and a 200 GiB disk. Increase those values for large assemblies if the Ubuntu host has capacity.

The default virtual display is suitable for installation and COM-oriented automation. If your workload depends heavily on interactive viewport performance, GPU rendering, ray tracing or large-model graphics, configure GPU passthrough separately and install the matching Windows GPU driver before relying on those workloads.

## Exact installation order

Use this order for a new deployment:

1. Extract this repository on Ubuntu.
2. Install Ubuntu KVM/libvirt/OVMF/swtpm prerequisites.
3. Log out and back in so `libvirt`/`kvm` group membership applies.
4. Download an official Windows 11 x64 ISO to the Ubuntu server.
5. Create `windows-vm.env` and configure the ISO path/VM sizing.
6. Create the Windows 11 VM.
7. Connect to the VM through the loopback-only VNC console over an SSH tunnel.
8. Install Windows 11 and complete Windows Update.
9. Install Python 3.11+ x64 in Windows with the Python launcher (`py`).
10. Install Autodesk Inventor 2026 in Windows normally.
11. Launch Inventor manually and finish Autodesk sign-in/licensing/first-run dialogs.
12. Transfer `dist/windows-bridge.zip` from Ubuntu into Windows.
13. Extract the bridge to `C:\InventorVmBridge` and run `install.ps1` as Administrator.
14. Verify the bridge locally in Windows with `test_bridge.ps1`.
15. On Ubuntu, save the Windows VM IPv4 address as `VM_IP` in `.bridge-client.env`. The recommended command is `bash scripts/linux/set-vm-ip.sh`; you can also pass the address explicitly.
16. Verify Ubuntu -> Windows -> Inventor COM with `scripts/linux/bridge-health.sh`.
17. Extract/configure Rishika on Ubuntu and run `bash scripts/linux/configure-rishika.sh /path/to/Rishika`.
18. Run Rishika's Windows/Inventor preflight test.
19. Start Rishika normally.

The remainder of this guide expands every step.

---

## 1. Extract the repository on Ubuntu

Choose a permanent directory. Example:

```bash
mkdir -p ~/inventor-on-linux-ubuntu
cd ~/inventor-on-linux-ubuntu
unzip /path/to/inventor-on-linux-ubuntu-vm-bridge.zip
```

If the ZIP creates a top-level `inventor-on-linux-ubuntu/` directory, `cd` into it before continuing.

## 2. Install Ubuntu virtualization prerequisites

Run:

```bash
bash scripts/linux/setup-host.sh
```

This installs KVM/QEMU, libvirt, `virt-install`, OVMF UEFI firmware, `swtpm`, VM console utilities, and supporting tools. It also adds the current Ubuntu user to the `libvirt` and `kvm` groups.

**Log out of Ubuntu and log back in after this step.** Group changes do not reliably apply to the current login shell.

After reconnecting, verify virtualization:

```bash
kvm-ok
virsh --connect qemu:///system list --all
```

`kvm-ok` should report that KVM acceleration can be used.

## 3. Download the Windows 11 ISO

Download an official Windows 11 x64 ISO from Microsoft using a browser/workstation and place it on the Ubuntu server, for example:

```text
/home/<ubuntu-user>/Downloads/Win11_English_x64.iso
```

The repository does not redistribute Windows installation media or a Windows license.

## 4. Configure the VM

From the repository root:

```bash
cp windows-vm.env.example windows-vm.env
nano windows-vm.env
```

At minimum, verify:

```bash
WINDOWS_ISO_SOURCE="$HOME/Downloads/Win11_English_x64.iso"
VM_NAME="inventor-win11"
VM_MEMORY_MIB="32768"
VM_VCPUS="8"
VM_DISK_GIB="200"
```

If the host has limited memory, 16 GB is Autodesk's minimum for smaller assemblies, but 32 GB is the recommended baseline. Do not allocate so much RAM or CPU that the Ubuntu host is starved.

The default network is libvirt NAT (`default`). This is appropriate when Rishika runs on the same Ubuntu host because Ubuntu can directly reach the guest's private address.

## 5. Create the Windows 11 VM

Run:

```bash
bash scripts/linux/create-windows-vm.sh
```

The script:

- copies the Windows ISO to libvirt's boot directory;
- creates a qcow2 disk;
- creates a Q35 VM;
- uses OVMF UEFI firmware;
- provides an emulated TPM 2.0;
- assigns the configured RAM and vCPUs;
- uses a SATA virtual disk and Intel e1000e NIC so the Windows installer does not depend on extra VirtIO storage/network drivers;
- binds the VNC console only to `127.0.0.1` on Ubuntu;
- boots the Windows installer.

It refuses to overwrite an existing domain with the same name.

## 6. Connect to the VM console securely

The VNC console is intentionally not exposed on the server network.

From your workstation, open an SSH tunnel to the Ubuntu server. With the default port:

```bash
ssh -L 5905:127.0.0.1:5905 <ubuntu-user>@<ubuntu-server>
```

Keep that SSH connection open. Then point TigerVNC Viewer or another VNC client at:

```text
127.0.0.1:5905
```

You should see the Windows installer.

## 7. Install Windows 11

Perform the normal Windows 11 installation:

1. Select the desired language/keyboard.
2. Install Windows 11 (Windows 11 Pro is a practical choice for this server VM).
3. Choose the virtual disk created by libvirt.
4. Complete Windows OOBE and create the Windows account that will run Inventor.
5. Reach the Windows desktop.
6. Run Windows Update repeatedly until there are no important pending updates requiring a restart.
7. Reboot when Windows requests it.

The VM is configured with UEFI and TPM 2.0 for Windows 11 compatibility.

For a server-style VM, prevent automatic sleep while on AC power. In an Administrator PowerShell window:

```powershell
powercfg /change standby-timeout-ac 0
powercfg /change hibernate-timeout-ac 0
```

Locking or disconnecting the desktop session later is fine; the Windows user must remain logged in when the bridge is controlling Inventor.

## 8. Install Python in Windows

Install current Python 3.11+ x64 from python.org. During installation, enable the Python launcher (`py`). Adding Python to PATH is useful but the bridge installer specifically checks for `py`.

Verify in PowerShell:

```powershell
py -3 --version
```

## 9. Install Autodesk Inventor 2026

Inside the Windows VM:

1. Download/install Autodesk Inventor 2026 using your normal Autodesk account/deployment method.
2. Install all Autodesk components required by your licensed Inventor installation.
3. Apply the Inventor updates you intend to use.
4. Launch Inventor manually.
5. Complete Autodesk Identity Manager/sign-in and licensing.
6. Dismiss or complete first-run dialogs.
7. Open a simple part once and confirm Inventor is usable before installing the bridge.

Keep Inventor installed in Windows. No Inventor files or Autodesk runtime components need to be copied to Ubuntu.

## 10. Transfer the Windows bridge

On Ubuntu, this repository contains:

```text
dist/windows-bridge.zip
```

Copy that ZIP into the Windows VM using VNC clipboard/file transfer, SMB/SCP tooling you already use, or another private transfer method.

Extract it to a persistent directory such as:

```text
C:\InventorVmBridge
```

Do not run it from a temporary/download ZIP view.

## 11. Install the bridge in Windows

Open **PowerShell as Administrator** in `C:\InventorVmBridge` and run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\install.ps1
```

The installer:

1. verifies the Python launcher;
2. creates `C:\InventorVmBridge\.venv`;
3. installs FastAPI, Uvicorn, pywin32 and bridge dependencies;
4. opens the configured private bridge TCP port in Windows Firewall;
5. registers the **Inventor VM Bridge** Scheduled Task for the current interactive user at logon;
6. starts the bridge;
7. runs the local bridge/Inventor test.

The bridge deliberately runs in the interactive Windows user session, not as a Session 0 Windows service. Inventor is a desktop COM application.

The supplied `windows_bridge/.env` and Ubuntu `.bridge-client.env` contain the same generated API token. Both are ignored by Git so the token is not intended to be committed.

`install.ps1` waits up to 45 seconds for the bridge `/health` endpoint. If startup still fails, it prints the bridge logs automatically instead of only reporting a connection-refused error.

## 12. Verify the bridge inside Windows

From `C:\InventorVmBridge`:

```powershell
.\test_bridge.ps1
```

The bridge will attach to a running `Inventor.Application` COM server. If Inventor is not running and `INVENTOR_START_IF_NEEDED=true`, it will attempt to start Inventor in the logged-in Windows session.

Bridge administration commands:

```powershell
.\start_bridge.ps1
.\stop_bridge.ps1
.\test_bridge.ps1
```

Logs are written to:

```text
C:\InventorVmBridge\logs\
```

## 13. Prepare the Ubuntu bridge client configuration

Return to the Ubuntu host and change into the root of this repository. The supplied package contains a hidden file named:

```text
.bridge-client.env
```

A normal `ls` does not show dotfiles. Verify it with:

```bash
pwd
ls -la .bridge-client.env
chmod 600 .bridge-client.env
```

The Ubuntu client configuration has four important values:

```dotenv
VM_NAME="inventor-win11"
VM_IP="192.168.122.123"
INVENTOR_BRIDGE_PORT="8765"
INVENTOR_BRIDGE_TOKEN="<same token used by C:\InventorVmBridge\.env>"
```

### `VM_IP` is the recommended bridge target

Set `VM_IP` explicitly rather than relying on automatic VM address discovery. This avoids a dependency on `qemu-guest-agent` and avoids differences between libvirt address sources.

For the VM used while preparing this package, the confirmed libvirt DHCP lease is:

```text
192.168.122.123
```

The supplied `.bridge-client.env` is already populated with that address. Verify the current lease on Ubuntu with:

```bash
virsh --connect qemu:///system domifaddr inventor-win11 --source lease
```

Expected shape:

```text
Name    MAC address          Protocol   Address
vnet0   52:54:00:...         ipv4       192.168.122.123/24
```

To detect the current DHCP lease and save it into `.bridge-client.env`, run:

```bash
bash scripts/linux/set-vm-ip.sh
```

Or, if you obtained the IPv4 address from `ipconfig` inside Windows, save it explicitly:

```bash
bash scripts/linux/set-vm-ip.sh 192.168.122.123
```

The helper updates only `VM_IP`; it does not change your API token.

If the VM is recreated or receives a different DHCP lease later, rerun `set-vm-ip.sh` before starting Rishika.

### Bridge token

The Linux value `INVENTOR_BRIDGE_TOKEN` must exactly match the Windows value in:

```text
C:\InventorVmBridge\.env
```

To inspect the Windows value without editing the file, run in PowerShell:

```powershell
Select-String -Path C:\InventorVmBridge\.env -Pattern '^INVENTOR_BRIDGE_TOKEN='
```

Do not post or commit that token.

### If `.bridge-client.env` is missing

Create it from the example:

```bash
cp .bridge-client.env.example .bridge-client.env
chmod 600 .bridge-client.env
nano .bridge-client.env
```

Fill in `VM_IP`, `INVENTOR_BRIDGE_PORT`, and `INVENTOR_BRIDGE_TOKEN` before continuing.

## 14. Verify from Ubuntu

First verify the address the client will actually use:

```bash
bash scripts/linux/vm-ip.sh
```

With this deployment it should print:

```text
192.168.122.123
```

Then test the complete route:

```bash
bash scripts/linux/bridge-health.sh
```

Expected result shape:

```json
{"status":"ready","worker_alive":true}
{"inventor_connected":true,"inventor_version":"2026.4"}
```

This proves:

```text
Ubuntu -> VM_IP:8765 -> Windows bridge -> pywin32 -> Inventor.Application
```

You can also test raw HTTP networking independently of the token:

```bash
curl -v --max-time 5 "http://$(bash scripts/linux/vm-ip.sh):8765/health"
```

If `vm-ip.sh` prints nothing or errors, verify `.bridge-client.env` contains `VM_IP`. If needed, refresh it with `bash scripts/linux/set-vm-ip.sh`.

Automatic discovery is still available as a fallback when `VM_IP` is absent. The script now tries the libvirt DHCP `lease` source first and tolerates unavailable `agent`/`arp` sources instead of aborting. Explicit `VM_IP` remains the recommended setup.

## 15. Install/configure Rishika on Ubuntu

Extract the supplied Rishika package to its permanent directory.

Synchronize Rishika with this repository's configured bridge target and token:

```bash
bash scripts/linux/configure-rishika.sh /path/to/Rishika
```

The script writes an explicit bridge URL based on `VM_IP`, for example:

```dotenv
INVENTOR_BACKEND=remote
INVENTOR_BRIDGE_URL=http://192.168.122.123:8765
INVENTOR_BRIDGE_TOKEN=<matching private token>
INVENTOR_VM_NAME=inventor-win11
INVENTOR_BRIDGE_PORT=8765
```

Using an explicit URL means Rishika does not need to perform its own libvirt IP discovery.

If the VM address changes later:

```bash
bash scripts/linux/set-vm-ip.sh
bash scripts/linux/configure-rishika.sh /path/to/Rishika
```

Then rerun `bridge-health.sh` before using the application.

## 16. Validate Rishika before normal use

From the Rishika directory:

```bash
python3 src/preflight.py --phase windows
```

Then test an actual Inventor file:

```bash
python3 scripts/test_inventor_bridge.py /path/to/example.ipt
```

For assemblies with referenced parts, send the assembly as a ZIP containing the root `.iam` and its referenced `.ipt` files with their relative directory layout preserved.

## 17. Normal startup order after installation

Once everything is installed, the daily/startup sequence is much shorter:

### Ubuntu

```bash
cd /path/to/inventor-on-linux-ubuntu
bash scripts/linux/start-windows-vm.sh
```

### Windows VM

1. Windows boots.
2. Sign in to the Windows account that owns the Autodesk/Inventor session.
3. The scheduled **Inventor VM Bridge** task starts automatically at logon.
4. Inventor may already be running; otherwise the bridge can start it when the first authenticated status/extraction request arrives.

After Windows login is complete, Ubuntu should report:

```bash
bash scripts/linux/bridge-health.sh
```

### Rishika

Start Rishika normally, for example:

```bash
cd /path/to/Rishika
./search_app.sh
```

No VNC connection needs to remain open during normal automation. VNC is only needed when you need to interact with the Windows desktop, Autodesk sign-in, dialogs, updates or troubleshooting.

## 18. Shutdown order

Close/stop Rishika work first. If desired, leave Inventor and the bridge running until Windows shuts down.

Request a clean VM shutdown from Ubuntu:

```bash
bash scripts/linux/stop-windows-vm.sh
```

Avoid `virsh destroy` except for recovery from a hung guest because it is equivalent to pulling power.

## 19. Diagnostics

Ubuntu-side checks:

```bash
bash scripts/linux/doctor.sh
bash scripts/linux/set-vm-ip.sh
bash scripts/linux/vm-ip.sh
bash scripts/linux/bridge-health.sh
```

Libvirt state:

```bash
virsh --connect qemu:///system list --all
virsh --connect qemu:///system dominfo inventor-win11
virsh --connect qemu:///system domifaddr inventor-win11 --source lease
```

Windows-side checks:

```powershell
Get-ScheduledTask -TaskName "Inventor VM Bridge"
Get-NetFirewallRule -DisplayName "Inventor VM Bridge TCP 8765"
cd C:\InventorVmBridge
.\test_bridge.ps1
Get-Content .\logs\bridge.err.log -Tail 100
```

If `/health` works but `/v1/status` fails, networking is working and the problem is specifically bridge -> COM -> Inventor. Check that the Autodesk user is logged in interactively, Inventor is licensed, and no modal Inventor/Autodesk dialog is waiting for input.

If Ubuntu cannot reach `/health`, verify the guest IPv4, Windows Firewall rule, libvirt network, bridge process and port.

## 20. Security notes

- Keep TCP 8765 on a private VM/LAN network; do not port-forward it from the public internet.
- `/v1/*` requires the generated API token.
- Keep `.bridge-client.env`, `windows_bridge/.env`, `windows-vm.env` and Rishika `.env` out of public source control.
- VNC binds only to Ubuntu `127.0.0.1`; use SSH tunnelling rather than opening the VNC port publicly.
- Rotate `INVENTOR_BRIDGE_TOKEN` in both Windows and Rishika/Ubuntu if the token is exposed.

## 21. Reference requirements

At the time this package was prepared, Autodesk lists Windows 10/11 x64 for Inventor 2026, with 32 GB RAM recommended (16 GB minimum for smaller assemblies), 40 GB for the installation, and DirectX-capable graphics. Microsoft requires Windows 11 VMs to provide UEFI/Secure-Boot-capable firmware and TPM 2.0. Ubuntu documents KVM/libvirt as its standard server virtualization stack.

Always use current Microsoft, Autodesk and Ubuntu documentation when changing OS versions, Inventor versions or virtualization hosts.
