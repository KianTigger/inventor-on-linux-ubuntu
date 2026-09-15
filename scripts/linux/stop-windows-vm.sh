#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common-vm.sh
source "$SCRIPT_DIR/common-vm.sh"

require_command virsh
if ! vm_exists; then
    echo "ERROR: VM '$VM_NAME' does not exist." >&2
    exit 1
fi

state="$(vm_state)"
if [[ "$state" != "running" ]]; then
    echo "$VM_NAME is not running (state: $state)."
    exit 0
fi

virsh_vm shutdown "$VM_NAME"
echo "Shutdown requested for $VM_NAME."
echo "Use 'virsh --connect $LIBVIRT_URI domstate $VM_NAME' to confirm it reaches 'shut off'."
