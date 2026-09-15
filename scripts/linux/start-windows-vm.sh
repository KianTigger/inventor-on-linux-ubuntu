#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common-vm.sh
source "$SCRIPT_DIR/common-vm.sh"

require_command virsh
if ! vm_exists; then
    echo "ERROR: VM '$VM_NAME' does not exist." >&2
    echo "Run: bash scripts/linux/create-windows-vm.sh" >&2
    exit 1
fi

state="$(vm_state)"
if [[ "$state" == "running" ]]; then
    echo "$VM_NAME is already running."
else
    virsh_vm start "$VM_NAME"
fi

echo "VM: $VM_NAME"
echo "Bridge IP (when Windows networking is ready):"
"$ROOT/scripts/linux/vm-ip.sh" || true
