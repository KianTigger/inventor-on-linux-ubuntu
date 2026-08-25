#!/usr/bin/env bash
# Create the Windows 11 staging VM used to install Inventor 2026.
set -euo pipefail
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
# shellcheck source=common-vm.sh
source "$SCRIPT_DIR/common-vm.sh"

require_vm_config
require_libvirt_access
vm_require_command virt-install "Run scripts/vm/setup-windows-vm-host.sh first."
vm_require_command ss "Install iproute2 (normally present on Ubuntu)."

if vm_domain_exists; then
    echo "ERROR: A libvirt domain named '$VM_NAME' already exists." >&2
    echo "       This script will not overwrite an existing VM." >&2
    exit 1
fi

if [[ -z "$WINDOWS_ISO_SOURCE" || ! -r "$WINDOWS_ISO_SOURCE" ]]; then
    echo "ERROR: WINDOWS_ISO_SOURCE is not a readable Windows 11 x64 ISO:" >&2
    echo "       ${WINDOWS_ISO_SOURCE:-<unset>}" >&2
    echo "       Edit windows-vm.env after downloading an official Windows 11 ISO." >&2
    exit 1
fi

for n in VM_MEMORY_MIB VM_VCPUS VM_DISK_GIB VM_VNC_PORT; do
    value="${!n}"
    if [[ ! "$value" =~ ^[0-9]+$ || "$value" -le 0 ]]; then
        echo "ERROR: $n must be a positive integer; found '$value'." >&2
        exit 1
    fi
done

if (( VM_MEMORY_MIB < 16384 )); then
    echo "WARNING: Inventor 2026 documents 16 GB as its minimum RAM for smaller assemblies." >&2
fi
if (( VM_DISK_GIB < 120 )); then
    echo "WARNING: VM_DISK_GIB=$VM_DISK_GIB is tight for Windows + Inventor + installer cache." >&2
fi

if [[ -e "$VM_DISK" ]]; then
    echo "ERROR: VM disk already exists: $VM_DISK" >&2
    exit 1
fi
if ss -ltn | awk '{print $4}' | grep -Eq "(^|:)${VM_VNC_PORT}$"; then
    echo "ERROR: TCP port $VM_VNC_PORT is already in use. Change VM_VNC_PORT in windows-vm.env." >&2
    exit 1
fi

for f in "$VM_UEFI_CODE" "$VM_UEFI_VARS"; do
    [[ -r "$f" ]] || { echo "ERROR: OVMF firmware file missing: $f" >&2; exit 1; }
done

# Stage the installer where the system libvirt QEMU process can read it.
sudo mkdir -p "$(dirname "$VM_WINDOWS_ISO")" "$(dirname "$VM_DISK")"
echo "Copying Windows ISO into libvirt storage..."
sudo cp --reflink=auto --sparse=always "$WINDOWS_ISO_SOURCE" "$VM_WINDOWS_ISO"
sudo chmod 0644 "$VM_WINDOWS_ISO"

# Ubuntu 22.04 updates normally know win11. Fall back to win10 metadata only
# for libosinfo tuning if the local database is older; UEFI/TPM are explicit.
os_variant="win11"
if ! virt-install --osinfo list 2>/dev/null | grep -qx 'win11'; then
    os_variant="win10"
    echo "WARNING: local libosinfo does not list win11; using win10 tuning metadata." >&2
fi

virt_args=(
    --connect qemu:///system
    --name "$VM_NAME"
    --memory "$VM_MEMORY_MIB"
    --vcpus "$VM_VCPUS"
    --cpu host-passthrough
    --machine q35
    --osinfo "$os_variant"
    --disk "path=$VM_DISK,format=qcow2,size=$VM_DISK_GIB,bus=sata,cache=none"
    --cdrom "$VM_WINDOWS_ISO"
    --network network=default,model=e1000e
    --graphics "vnc,listen=127.0.0.1,port=$VM_VNC_PORT"
    --video qxl
    --boot "loader=$VM_UEFI_CODE,loader.readonly=yes,loader.type=pflash,loader_secure=yes,nvram.template=$VM_UEFI_VARS"
    --features smm.state=on
    --tpm backend.type=emulator,backend.version=2.0,model=tpm-crb
    --noautoconsole
)

echo "Validating libvirt VM definition..."
virt-install "${virt_args[@]}" --dry-run >/dev/null

echo "Creating $VM_NAME..."
if ! virt-install "${virt_args[@]}"; then
    echo "ERROR: virt-install failed. The staged ISO was left at: $VM_WINDOWS_ISO" >&2
    echo "       If a partial disk was created, inspect/remove it before retrying: $VM_DISK" >&2
    exit 1
fi

printf '\nCreated and started VM: %s\n' "$VM_NAME"
printf 'Disk: %s (%s GiB virtual size)\n' "$VM_DISK" "$VM_DISK_GIB"
printf 'Firmware: UEFI Secure Boot + emulated TPM 2.0\n'
printf 'Network: libvirt default NAT (e1000e)\n'
print_vnc_tunnel
printf '\nContinue with docs/windows-vm.md.\n'
