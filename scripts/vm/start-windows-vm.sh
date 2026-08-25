#!/usr/bin/env bash
# Start the staging VM only when its filesystem is not guestmounted.
set -euo pipefail
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
# shellcheck source=common-vm.sh
source "$SCRIPT_DIR/common-vm.sh"

require_vm_config
require_libvirt_access
vm_require_command mountpoint

if ! vm_domain_exists; then
    echo "ERROR: VM '$VM_NAME' does not exist. Run create-windows-vm.sh first." >&2
    exit 1
fi
if mountpoint -q "$VM_MOUNT"; then
    echo "ERROR: $VM_MOUNT is still mounted from the VM." >&2
    echo "       Run: bash scripts/vm/unmount-windows-vm.sh" >&2
    exit 1
fi

state="$(vm_state)"
if [[ "$state" == "running" ]]; then
    echo "$VM_NAME is already running."
else
    virsh start "$VM_NAME"
fi
print_vnc_tunnel
