#!/usr/bin/env bash
# Shared helpers for the Windows staging VM workflow.

VM_SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
VM_SCRIPT_DIR="$(cd "$(dirname "$VM_SCRIPT_PATH")" && pwd)"
PROJECT_DIR="$(cd "$VM_SCRIPT_DIR/../.." && pwd)"
VM_CONFIG_FILE="${WINDOWS_VM_CONFIG:-$PROJECT_DIR/windows-vm.env}"

: "${VM_NAME:=inventor-win11}"
: "${VM_MEMORY_MIB:=32768}"
: "${VM_VCPUS:=8}"
: "${VM_DISK_GIB:=160}"
: "${VM_VNC_PORT:=5905}"
: "${VM_MOUNT:=/mnt/windows}"
: "${VM_UEFI_CODE:=/usr/share/OVMF/OVMF_CODE_4M.ms.fd}"
: "${VM_UEFI_VARS:=/usr/share/OVMF/OVMF_VARS_4M.ms.fd}"
: "${WINDOWS_ISO_SOURCE:=}"
: "${VM_DISK:=/var/lib/libvirt/images/${VM_NAME}.qcow2}"
: "${VM_WINDOWS_ISO:=/var/lib/libvirt/boot/${VM_NAME}-windows.iso}"

if [[ -f "$VM_CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$VM_CONFIG_FILE"
fi

export LIBVIRT_DEFAULT_URI="${LIBVIRT_DEFAULT_URI:-qemu:///system}"

vm_require_command() {
    local cmd="$1"
    local hint="${2:-}"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: Required command not found: $cmd" >&2
        [[ -n "$hint" ]] && echo "       $hint" >&2
        return 1
    fi
}

require_vm_config() {
    if [[ ! -f "$VM_CONFIG_FILE" ]]; then
        echo "ERROR: VM config not found: $VM_CONFIG_FILE" >&2
        echo "       Run: cp windows-vm.env.example windows-vm.env" >&2
        echo "       Then edit WINDOWS_ISO_SOURCE and any VM sizing values." >&2
        return 1
    fi
}

vm_domain_exists() {
    virsh dominfo "$VM_NAME" >/dev/null 2>&1
}

vm_state() {
    virsh domstate "$VM_NAME" 2>/dev/null | tr -d '\r' | xargs
}

require_libvirt_access() {
    vm_require_command virsh "Run scripts/vm/setup-windows-vm-host.sh first." || return 1
    if ! virsh list --all >/dev/null 2>&1; then
        echo "ERROR: Cannot access system libvirt as $(id -un)." >&2
        echo "       If setup-windows-vm-host.sh just added you to libvirt/kvm," >&2
        echo "       log out completely and log back in, then retry." >&2
        return 1
    fi
}

print_vnc_tunnel() {
    local host="${1:-AI-Server}"
    printf '\nWindows console (from your workstation):\n'
    printf '  ssh -N -L %s:127.0.0.1:%s %s@%s\n' "$VM_VNC_PORT" "$VM_VNC_PORT" "$(id -un)" "$host"
    printf 'Then connect a VNC viewer to: 127.0.0.1:%s\n' "$VM_VNC_PORT"
}
