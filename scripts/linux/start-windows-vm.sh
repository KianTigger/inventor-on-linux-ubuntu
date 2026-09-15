#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[[ -f "$ROOT/windows-vm.env" ]] && source "$ROOT/windows-vm.env"
VM_NAME="${VM_NAME:-inventor-win11}"

state="$(virsh domstate "$VM_NAME" 2>/dev/null | tr -d '\r' || true)"
if [[ "$state" == "running" ]]; then
    echo "$VM_NAME is already running."
else
    virsh start "$VM_NAME"
fi

echo "VM: $VM_NAME"
echo "Bridge IP (when available):"
"$ROOT/scripts/linux/vm-ip.sh" || true
