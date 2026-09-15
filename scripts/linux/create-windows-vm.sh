#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common-vm.sh
source "$SCRIPT_DIR/common-vm.sh"

require_command virsh
require_command virt-install
require_command osinfo-query

if [[ ! -f "$ROOT/windows-vm.env" ]]; then
    echo "ERROR: $ROOT/windows-vm.env does not exist." >&2
    echo "Run: cp windows-vm.env.example windows-vm.env" >&2
    echo "Then edit WINDOWS_ISO_SOURCE and any VM sizing values." >&2
    exit 1
fi

if vm_exists; then
    echo "ERROR: libvirt domain '$VM_NAME' already exists." >&2
    echo "This script will not overwrite an existing VM." >&2
    exit 1
fi

if [[ ! -f "$WINDOWS_ISO_SOURCE" ]]; then
    echo "ERROR: Windows ISO not found: $WINDOWS_ISO_SOURCE" >&2
    echo "Download an official Windows 11 x64 ISO and update WINDOWS_ISO_SOURCE in windows-vm.env." >&2
    exit 1
fi

OVMF_CODE="$(find_ovmf_code || true)"
OVMF_VARS="$(find_ovmf_vars || true)"
if [[ -z "$OVMF_CODE" || -z "$OVMF_VARS" ]]; then
    echo "ERROR: Secure-Boot-capable OVMF firmware was not found." >&2
    echo "Verify that the Ubuntu 'ovmf' package is installed." >&2
    exit 1
fi

# Copy installation media into libvirt's boot directory so qemu:///system does
# not need permission to traverse the user's home directory.
sudo install -d -m 0755 "$(dirname "$VM_WINDOWS_ISO")"
sudo install -m 0644 "$WINDOWS_ISO_SOURCE" "$VM_WINDOWS_ISO"

# Ensure the default/configured virtual network exists and is active.
if ! virsh_vm net-info "$VM_NETWORK" >/dev/null 2>&1; then
    echo "ERROR: libvirt network '$VM_NETWORK' does not exist." >&2
    echo "For a standard install, restore/start libvirt's 'default' NAT network." >&2
    exit 1
fi
virsh_vm net-autostart "$VM_NETWORK" >/dev/null || true
if ! virsh_vm net-info "$VM_NETWORK" | grep -q 'Active:.*yes'; then
    virsh_vm net-start "$VM_NETWORK" >/dev/null
fi

OS_VARIANT="win11"
if ! osinfo-query os short-id 2>/dev/null | awk '{print $1}' | grep -qx 'win11'; then
    OS_VARIANT="win10"
    echo "NOTE: local osinfo database has no win11 entry; using win10 metadata for device defaults."
fi

echo "Creating Windows VM '$VM_NAME'..."
echo "  RAM:       ${VM_MEMORY_MIB} MiB"
echo "  vCPUs:     ${VM_VCPUS}"
echo "  Disk:      ${VM_DISK_GIB} GiB ($VM_DISK)"
echo "  Network:   $VM_NETWORK"
echo "  VNC:       127.0.0.1:$VM_VNC_PORT"
echo "  UEFI code: $OVMF_CODE"
echo "  TPM:       2.0 emulator"

virt-install \
    --connect "$LIBVIRT_URI" \
    --name "$VM_NAME" \
    --memory "$VM_MEMORY_MIB" \
    --vcpus "$VM_VCPUS" \
    --cpu host-passthrough \
    --machine q35 \
    --os-variant "$OS_VARIANT" \
    --disk "path=$VM_DISK,size=$VM_DISK_GIB,format=qcow2,bus=sata,discard=unmap" \
    --cdrom "$VM_WINDOWS_ISO" \
    --network "network=$VM_NETWORK,model=e1000e" \
    --graphics "vnc,listen=127.0.0.1,port=$VM_VNC_PORT" \
    --video vga \
    --controller usb,model=qemu-xhci \
    --input tablet,bus=usb \
    --boot "loader=$OVMF_CODE,loader.readonly=yes,loader.type=pflash,nvram.template=$OVMF_VARS" \
    --features smm=on \
    --tpm backend.type=emulator,backend.version=2.0,model=tpm-crb \
    --noautoconsole

echo
echo "VM created and started."
echo "From your workstation, create an SSH tunnel:"
echo "  ssh -L ${VM_VNC_PORT}:127.0.0.1:${VM_VNC_PORT} <ubuntu-user>@<ubuntu-server>"
echo "Then connect a VNC viewer to: 127.0.0.1:${VM_VNC_PORT}"
echo "Complete the normal Windows 11 installation, Windows Update, Python installation, and Autodesk Inventor installation."
