#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Load documented defaults first, then local overrides.
# shellcheck disable=SC1091
source "$ROOT/windows-vm.env.example"
if [[ -f "$ROOT/windows-vm.env" ]]; then
    # shellcheck disable=SC1091
    source "$ROOT/windows-vm.env"
fi

LIBVIRT_URI="${LIBVIRT_URI:-qemu:///system}"
VM_NAME="${VM_NAME:-inventor-win11}"
VM_MEMORY_MIB="${VM_MEMORY_MIB:-32768}"
VM_VCPUS="${VM_VCPUS:-8}"
VM_DISK_GIB="${VM_DISK_GIB:-200}"
VM_DISK="${VM_DISK:-/var/lib/libvirt/images/${VM_NAME}.qcow2}"
VM_NETWORK="${VM_NETWORK:-default}"
VM_VNC_PORT="${VM_VNC_PORT:-5905}"
INVENTOR_BRIDGE_PORT="${INVENTOR_BRIDGE_PORT:-8765}"

virsh_vm() {
    virsh --connect "$LIBVIRT_URI" "$@"
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "ERROR: Required command '$1' was not found." >&2
        exit 1
    }
}

vm_exists() {
    virsh_vm dominfo "$VM_NAME" >/dev/null 2>&1
}

vm_state() {
    virsh_vm domstate "$VM_NAME" 2>/dev/null | tr -d '\r' | xargs
}

find_ovmf_code() {
    if [[ -n "${VM_UEFI_CODE:-}" && -f "$VM_UEFI_CODE" ]]; then
        printf '%s\n' "$VM_UEFI_CODE"
        return 0
    fi
    local candidate
    for candidate in \
        /usr/share/OVMF/OVMF_CODE_4M.ms.fd \
        /usr/share/OVMF/OVMF_CODE_4M.secboot.fd \
        /usr/share/OVMF/OVMF_CODE.ms.fd \
        /usr/share/OVMF/OVMF_CODE.secboot.fd; do
        [[ -f "$candidate" ]] && { printf '%s\n' "$candidate"; return 0; }
    done
    return 1
}

find_ovmf_vars() {
    if [[ -n "${VM_UEFI_VARS_TEMPLATE:-}" && -f "$VM_UEFI_VARS_TEMPLATE" ]]; then
        printf '%s\n' "$VM_UEFI_VARS_TEMPLATE"
        return 0
    fi
    local candidate
    for candidate in \
        /usr/share/OVMF/OVMF_VARS_4M.ms.fd \
        /usr/share/OVMF/OVMF_VARS_4M.fd \
        /usr/share/OVMF/OVMF_VARS.ms.fd \
        /usr/share/OVMF/OVMF_VARS.fd; do
        [[ -f "$candidate" ]] && { printf '%s\n' "$candidate"; return 0; }
    done
    return 1
}
