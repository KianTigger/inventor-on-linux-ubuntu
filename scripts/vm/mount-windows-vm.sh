#!/usr/bin/env bash
# Mount the offline Windows VM filesystem read-only at /mnt/windows.
set -euo pipefail
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
# shellcheck source=common-vm.sh
source "$SCRIPT_DIR/common-vm.sh"

require_vm_config
require_libvirt_access
vm_require_command guestmount "Install libguestfs-tools with setup-windows-vm-host.sh."
vm_require_command mountpoint

if ! vm_domain_exists; then
    echo "ERROR: VM '$VM_NAME' does not exist." >&2
    exit 1
fi

state="$(vm_state)"
if [[ "$state" != "shut off" ]]; then
    echo "ERROR: VM '$VM_NAME' must be completely shut off before mounting its Windows filesystem." >&2
    echo "       Current state: $state" >&2
    echo "       In Windows, run 'powercfg /h off', disable/decrypt BitLocker, then shut down." >&2
    exit 1
fi

if mountpoint -q "$VM_MOUNT"; then
    echo "$VM_MOUNT is already mounted."
    exit 0
fi

sudo mkdir -p "$VM_MOUNT"
sudo chown "$(id -u):$(id -g)" "$VM_MOUNT"

echo "Mounting $VM_NAME read-only at $VM_MOUNT..."
if ! guestmount -d "$VM_NAME" -i --ro \
        -o "uid=$(id -u)" -o "gid=$(id -g)" \
        "$VM_MOUNT"; then
    cat >&2 <<'MSG'
ERROR: guestmount could not inspect/mount the Windows filesystem.
Common causes:
  - Windows hibernation/Fast Startup was not disabled (run: powercfg /h off)
  - BitLocker/Device Encryption is still enabled (run: manage-bde -status C:)
  - Windows was not shut down cleanly
See docs/windows-vm.md for the required Windows preparation steps.
MSG
    exit 1
fi

if [[ ! -d "$VM_MOUNT/Windows/System32" ]]; then
    guestunmount "$VM_MOUNT" || true
    echo "ERROR: libguestfs mounted a filesystem, but it does not look like the Windows C: drive." >&2
    exit 1
fi

printf 'Mounted read-only: %s -> %s\n' "$VM_NAME" "$VM_MOUNT"
printf 'Set WINDOWS_MOUNT="%s" in inventor.env (the default already matches).\n' "$VM_MOUNT"
printf 'Next: bash scripts/doctor.sh\n'
