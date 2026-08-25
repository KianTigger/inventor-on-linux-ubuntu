# Windows 11 staging VM on Ubuntu 22.04

This workflow creates a Windows 11 VM on the same Ubuntu server so you can install Autodesk Inventor 2026 in Windows and then expose that **offline Windows filesystem** to the Wine rebuild at `/mnt/windows`.

The Windows VM is a staging/source machine. It does **not** need to remain running when you use Inventor through Wine.

## Architecture

```text
Ubuntu 22.04 server
├── KVM/QEMU + libvirt
│   └── Windows 11 staging VM
│       └── Inventor 2026 installed with normal Autodesk licensing/SSO
│
└── VM shut down
    └── libguestfs mounts Windows C: read-only at /mnt/windows
        ├── export-registry.sh
        └── rebuild-prefix.sh
            └── ~/.wine-inventor2026
```

The VM scripts deliberately use:

- KVM/QEMU and system libvirt (`qemu:///system`);
- Windows 11 x64;
- Q35 machine type;
- UEFI firmware with Microsoft Secure Boot keys;
- an emulated TPM 2.0 (`swtpm`);
- libvirt's default NAT network;
- a SATA virtual disk and Intel `e1000e` virtual NIC so the Windows installer does not depend on VirtIO storage/network drivers;
- a VNC console bound only to `127.0.0.1` on the server and accessed through SSH tunnelling;
- a read-only `guestmount` of the powered-off VM for the Linux-side source extraction.

No NVIDIA GPU passthrough is configured by default. For this repository the VM's purpose is to install, license and stage the Windows files rather than provide the final production Inventor graphics path. GPU passthrough can be added later if the Windows Inventor installer/first launch proves unable to operate with the virtual display, but it complicates ownership of the RTX GPU and should not be the first configuration.

## Requirements and sizing

Autodesk's Inventor 2026 requirements list 16 GB RAM as the minimum for smaller assemblies and 32 GB as recommended, with about 40 GB required for the installer plus full installation. The included VM defaults therefore use:

```text
RAM:     32 GiB
vCPUs:   8
Disk:    160 GiB qcow2 (thin provisioned)
Network: NAT
```

You can lower the VM to 16 GiB RAM if the Linux server cannot spare 32 GiB while staging, but 32 GiB is preferred.

The Linux host also needs hardware virtualization (`/dev/kvm`).

### 2026 Secure Boot certificate transition

Microsoft transitioned UEFI signing from the 2011 certificate authorities to the 2023 CAs on **June 26, 2026**. Ubuntu published `ovmf` `2022.02-3ubuntu0.22.04.6` for Jammy with the Microsoft 2023 keys added to the default enrollment. Because current Windows 11 media may rely on those keys, `setup-windows-vm-host.sh` requires that OVMF update or newer rather than creating a Secure Boot VM with stale firmware.

Check manually with:

```bash
dpkg-query -W ovmf
apt-cache policy ovmf
```

If the installed/candidate version is older, make sure `jammy-updates` is enabled before continuing.

### Licensing / virtualization

The VM still uses Autodesk's normal installer, account and licensing. Check that your Autodesk entitlement permits virtual installation/use. Autodesk states that Inventor can be installed in virtual environments when the VM meets the relevant product requirements, but support may require reproducing a problem outside the virtualization layer.

Useful references:

- Ubuntu libvirt: https://ubuntu.com/server/docs/how-to/virtualisation/libvirt/
- Windows 11 requirements: https://learn.microsoft.com/windows/whats-new/windows-11-requirements
- Inventor 2026 requirements: https://www.autodesk.com/support/technical/article/caas/sfdcarticles/sfdcarticles/System-requirements-for-Autodesk-Inventor-2026.html
- Autodesk virtual environments: https://www.autodesk.com/support/technical/article/caas/sfdcarticles/sfdcarticles/Virtual-Environments-when-using-Autodesk-software.html
- `guestmount`: https://libguestfs.org/guestmount.1.html

---

## 1. Obtain an official Windows 11 x64 ISO

Download a Windows 11 x64 ISO from Microsoft using your normal licensed installation path. The repository does not redistribute Windows installation media or product keys.

If the ISO is initially on another computer, copy it to the Ubuntu server. For example, from that computer:

```bash
scp /path/to/Win11_English_x64.iso ai4@AI-Server:~/Downloads/
```

Use your real SSH hostname/IP and username.

Do **not** put the ISO inside this Git repository.

---

## 2. Create the VM configuration

From the repository root:

```bash
cp windows-vm.env.example windows-vm.env
nano windows-vm.env
```

At minimum, set the ISO path:

```bash
WINDOWS_ISO_SOURCE="$HOME/Downloads/Win11_English_x64.iso"
```

The important defaults are:

```bash
VM_NAME="inventor-win11"
VM_MEMORY_MIB="32768"
VM_VCPUS="8"
VM_DISK_GIB="160"
VM_VNC_PORT="5905"
VM_MOUNT="/mnt/windows"
```

`windows-vm.env` is gitignored.

Keep this consistent with `inventor.env`:

```bash
WINDOWS_MOUNT="/mnt/windows"
```

---

## 3. Install KVM/libvirt on Ubuntu

Run as the normal Linux account that owns this repository:

```bash
bash scripts/vm/setup-windows-vm-host.sh
```

It installs:

- `qemu-kvm`
- `libvirt-daemon-system`
- `libvirt-clients`
- `virtinst`
- `ovmf`
- `swtpm` / `swtpm-tools`
- `libguestfs-tools`
- `cpu-checker`
- `osinfo-db`

It also enables `libvirtd`, adds your account to the `libvirt` and `kvm` groups, verifies `/dev/kvm`, and enables libvirt's standard NAT network.

### Log out after this step

Group membership changes do not affect the current login session. Log out completely and reconnect over SSH before proceeding:

```bash
exit
```

Then reconnect and verify:

```bash
id
virsh --connect qemu:///system list --all
bash scripts/vm/doctor-windows-vm.sh
```

Your group list should include both `libvirt` and `kvm`.

---

## 4. Create and start the Windows VM

Run:

```bash
bash scripts/vm/create-windows-vm.sh
```

The script:

1. copies your Windows ISO into `/var/lib/libvirt/boot/`;
2. creates a thin-provisioned QCOW2 disk under `/var/lib/libvirt/images/`;
3. configures Q35 + host CPU passthrough;
4. configures UEFI Secure Boot using Ubuntu's Microsoft-keyed OVMF images;
5. configures an emulated TPM 2.0;
6. attaches the Windows ISO;
7. configures NAT networking with `e1000e`;
8. starts the VM with VNC bound to server localhost only.

The VM is created in **system libvirt**, not a per-user QEMU session.

Check it with:

```bash
virsh list --all
virsh dominfo inventor-win11
```

---

## 5. Connect to the VM console securely

The default VNC port is `5905`, but it is intentionally listening only on the server's loopback interface. Do not open TCP 5905 in UFW or your external firewall.

From the computer where you want to view the Windows installer, create an SSH tunnel:

```bash
ssh -N -L 5905:127.0.0.1:5905 ai4@AI-Server
```

Keep that SSH process running. Then open any VNC viewer on the same client computer and connect to:

```text
127.0.0.1:5905
```

If you changed `VM_VNC_PORT`, use that port on both sides of the tunnel.

### If you miss "Press any key to boot from CD/DVD"

The Windows ISO may briefly prompt for a key. If the VM reaches an empty boot target before you connect, reset it:

```bash
virsh reset inventor-win11
```

Then reconnect immediately through VNC and press a key when prompted.

---

## 6. Install Windows 11

Perform a normal Windows 11 installation.

The VM is already configured with the major Windows 11 virtualization requirements:

- UEFI;
- Secure Boot;
- TPM 2.0;
- at least 2 virtual CPUs;
- at least 64 GB storage (the repository defaults to 160 GB).

The virtual disk is SATA and the NIC is `e1000e`, specifically to avoid requiring extra VirtIO drivers during Setup.

After installation:

1. let Windows Update finish;
2. install a browser if needed;
3. verify networking works;
4. optionally verify TPM/Secure Boot from Windows.

PowerShell checks:

```powershell
Get-Tpm
Confirm-SecureBootUEFI
```

---

## 7. Install Inventor 2026 inside Windows

Use the official Autodesk installer and your valid Autodesk entitlement.

For compatibility with the Linux rebuild:

1. install **Autodesk Inventor 2026 Professional**;
2. use the normal/default Autodesk installation locations;
3. keep Autodesk Identity Manager and Autodesk Licensing components installed;
4. sign in through Autodesk SSO;
5. launch Inventor at least once and confirm it gets far enough to initialize the installed product and licensing state;
6. close Inventor normally.

The Linux scripts expect paths such as:

```text
C:\Program Files\Autodesk\Inventor 2026
C:\Program Files\Autodesk\AdskIdentityManager\Current
C:\Program Files\Common Files\Autodesk Shared
C:\Program Files (x86)\Common Files\Autodesk Shared\AdskLicensing
C:\ProgramData\Autodesk
```

### Inventor update/build warning

The Wine workflow contains a fixed-offset patch for `OGSFactory.dll`. `rebuild-prefix.sh` checks the source bytes before applying it and **refuses to patch an unknown Inventor build**.

Until you have successfully built the Wine prefix, avoid deliberately updating Inventor beyond the build you are trying to reproduce. If Autodesk's installer supplies a newer 2026 build, the rebuild safety check may stop and the patch will need to be re-derived for that binary.

---

## 8. Prepare Windows for an offline NTFS mount

This step is mandatory before Linux accesses the Windows filesystem.

Open **Command Prompt or PowerShell as Administrator** inside the VM.

### Disable hibernation and Fast Startup

Run:

```powershell
powercfg /h off
```

Fast Startup uses the hibernation mechanism. Disabling hibernation prevents Windows from leaving the NTFS volume in a hibernated state that Linux tools may refuse to mount.

### Check BitLocker / Device Encryption

Run:

```powershell
manage-bde -status C:
```

If C: is encrypted or encryption is in progress, decrypt it:

```powershell
manage-bde -off C:
```

Do not proceed until:

```powershell
manage-bde -status C:
```

shows the C: volume fully decrypted (0% encrypted / decryption complete).

The read-only Linux mount is intended to consume an ordinary offline NTFS filesystem. An encrypted C: drive defeats that simple source workflow.

---

## 9. Shut Windows down completely

Use **Shut down** in Windows. Do not suspend or hibernate the VM.

You can also request a clean ACPI shutdown from Linux:

```bash
bash scripts/vm/stop-windows-vm.sh
```

Verify:

```bash
virsh domstate inventor-win11
```

It must report:

```text
shut off
```

The mount helper refuses to mount the VM while it is running.

---

## 10. Mount the Windows VM at `/mnt/windows`

Run:

```bash
bash scripts/vm/mount-windows-vm.sh
```

This uses libguestfs/`guestmount` to inspect the libvirt domain and mounts the Windows C: drive **read-only** at the configured mountpoint.

Verify:

```bash
ls -la /mnt/windows
ls -la "/mnt/windows/Program Files/Autodesk/Inventor 2026"
```

The top-level tree should resemble:

```text
/mnt/windows/
├── Program Files
├── Program Files (x86)
├── ProgramData
├── Users
└── Windows
```

If mounting fails, re-check:

```text
powercfg /h off
manage-bde -status C:
```

and confirm the VM is fully shut down.

---

## 11. Feed the VM into the Inventor-on-Wine rebuild

With the VM mounted read-only:

```bash
bash scripts/doctor.sh
```

Resolve any missing Windows-source failures, then:

```bash
bash scripts/export-registry.sh
bash scripts/rebuild-prefix.sh
bash scripts/install-wbemprox-patch.sh
bash scripts/setup-user-integration.sh
```

The registry export is especially important because the Windows registry hives are now available offline under the mounted VM filesystem.

After the Wine prefix has been built, the staging VM does not need to remain mounted.

---

## 12. Unmount before starting Windows again

Run:

```bash
bash scripts/vm/unmount-windows-vm.sh
```

Only then start the VM again:

```bash
bash scripts/vm/start-windows-vm.sh
```

The start helper refuses to start Windows while `/mnt/windows` is still mounted.

### Lifecycle rule

Always use one state or the other:

```text
Windows VM RUNNING
    /mnt/windows must be unmounted

Windows VM SHUT OFF
    /mnt/windows may be mounted read-only
```

Never run Windows and modify its disk image concurrently from Linux.

---

## VM maintenance commands

### Full VM preflight/status report

```bash
bash scripts/vm/doctor-windows-vm.sh
```

### Status

```bash
virsh list --all
virsh domstate inventor-win11
```

### Start

```bash
bash scripts/vm/start-windows-vm.sh
```

### Clean shutdown

```bash
bash scripts/vm/stop-windows-vm.sh
```

### Force power-off (last resort only)

```bash
virsh destroy inventor-win11
```

`virsh destroy` is equivalent to removing power. Use it only if Windows is unresponsive, then boot Windows again and perform a normal shutdown before mounting the filesystem.

### Remove the VM

Only if you intentionally want to discard it:

```bash
virsh undefine inventor-win11 --nvram --tpm
sudo rm -f /var/lib/libvirt/images/inventor-win11.qcow2
sudo rm -f /var/lib/libvirt/boot/inventor-win11-windows.iso
```

Double-check the configured VM name/disk paths before deleting anything.

---

## Troubleshooting

### `/dev/kvm` is missing

Check whether virtualization is exposed by the CPU/firmware:

```bash
lscpu | grep -i virtualization
sudo kvm-ok
```

On a physical server, enable Intel VT-x/VT-d or AMD-V/IOMMU in system firmware as appropriate.

### `virsh` says permission denied

The setup script adds your user to `libvirt` and `kvm`, but the current login will not pick that up automatically. Log out completely and reconnect.

Check:

```bash
id
virsh --connect qemu:///system list --all
```

### Windows has no internet

Check the libvirt NAT network:

```bash
virsh net-info default
virsh net-dhcp-leases default
```

It should be active and set to autostart.

### VNC connection refused

Check that the VM is running and that the configured VNC port is listening on server localhost:

```bash
virsh domstate inventor-win11
ss -ltn | grep 5905
```

Then recreate the SSH tunnel from your client.

### Windows installer cannot see the disk

The repository VM uses a SATA disk specifically to avoid this problem. Check the domain XML if you changed the storage bus:

```bash
virsh dumpxml inventor-win11 | grep -A8 '<disk type='
```

If you switch to VirtIO storage later, Windows needs the VirtIO storage drivers during installation.

### `guestmount` cannot inspect Windows

The common causes are:

- VM is still running;
- Windows hibernation/Fast Startup was left enabled;
- C: is BitLocker/device encrypted;
- Windows was hard-powered-off and NTFS is dirty.

Boot Windows, correct those conditions, perform a normal shutdown, then retry.

### Inventor will not launch inside the VM because of graphics

The staging VM intentionally does not claim to meet Autodesk's recommended physical GPU configuration. First confirm whether you actually need Inventor's 3D viewport in the VM; for this repository the VM primarily provides a complete installed source tree and licensing/identity components.

If the product cannot initialize without a DirectX-capable physical GPU, PCIe GPU passthrough is the next option. That requires IOMMU/VFIO planning and temporarily removes the selected GPU from the Linux NVIDIA driver while the VM owns it. Do not configure passthrough casually on a server already using GPUs for compute/display workloads.
