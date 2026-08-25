#!/usr/bin/env bash
# Unmount the offline Windows source before starting the VM again.
set -euo pipefail
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
# shellcheck source=common-vm.sh
source "$SCRIPT_DIR/common-vm.sh"

require_vm_config
vm_require_command guestunmount "Install libguestfs-tools with setup-windows-vm-host.sh."
vm_require_command mountpoint

if ! mountpoint -q "$VM_MOUNT"; then
    echo "$VM_MOUNT is not mounted."
    exit 0
fi

guestunmount "$VM_MOUNT"
echo "Unmounted $VM_MOUNT. It is now safe to start the Windows VM."
