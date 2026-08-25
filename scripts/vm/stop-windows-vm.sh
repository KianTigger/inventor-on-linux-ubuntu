#!/usr/bin/env bash
# Request a clean Windows shutdown and wait until the VM is off.
set -euo pipefail
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
# shellcheck source=common-vm.sh
source "$SCRIPT_DIR/common-vm.sh"

require_vm_config
require_libvirt_access

if ! vm_domain_exists; then
    echo "ERROR: VM '$VM_NAME' does not exist." >&2
    exit 1
fi

state="$(vm_state)"
if [[ "$state" == "shut off" ]]; then
    echo "$VM_NAME is already shut off."
    exit 0
fi

virsh shutdown "$VM_NAME"
printf 'Waiting for %s to shut down cleanly' "$VM_NAME"
for _ in $(seq 1 90); do
    sleep 2
    state="$(vm_state)"
    if [[ "$state" == "shut off" ]]; then
        printf '\n%s is shut off.\n' "$VM_NAME"
        exit 0
    fi
    printf '.'
done
printf '\nTimed out waiting for a clean shutdown.\n' >&2
printf 'Use the Windows UI to shut down. Avoid virsh destroy unless Windows is unresponsive.\n' >&2
exit 1
