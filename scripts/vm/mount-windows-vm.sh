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
vm_require_command guestfish "Install libguestfs-tools with setup-windows-vm-host.sh."
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

if [[ ! -r "$VM_DISK" ]]; then
    # This is expected for a libvirt-owned image when running as an ordinary
    # user. The actual libguestfs commands below run through sudo.
    if ! sudo test -r "$VM_DISK"; then
        echo "ERROR: VM disk is not readable even with sudo: $VM_DISK" >&2
        exit 1
    fi
fi

sudo mkdir -p "$VM_MOUNT"
sudo chown "$(id -u):$(id -g)" "$VM_MOUNT"

# guestmount is launched as root so FUSE must allow the resulting mount to be
# traversed by the normal repository user.
if [[ ! -f /etc/fuse.conf ]] || ! grep -qE '^[[:space:]]*user_allow_other([[:space:]]|$)' /etc/fuse.conf; then
    echo "Enabling FUSE user_allow_other in /etc/fuse.conf..."
    sudo touch /etc/fuse.conf
    echo 'user_allow_other' | sudo tee -a /etc/fuse.conf >/dev/null
fi

echo "Inspecting $VM_DISK for the Windows C: partition..."

mapfile -t filesystems < <(
    sudo env LIBGUESTFS_BACKEND=direct \
        guestfish --ro -a "$VM_DISK" <<'GUESTFISH'
run
list-filesystems
GUESTFISH
)

windows_partition=""
for line in "${filesystems[@]}"; do
    # guestfish normally prints entries such as: /dev/sda3: ntfs
    partition="${line%%:*}"
    fstype="${line#*: }"

    [[ "$partition" == /dev/* ]] || continue
    [[ "$fstype" == ntfs* ]] || continue

    is_windows="$(
        sudo env LIBGUESTFS_BACKEND=direct \
            guestfish --ro -a "$VM_DISK" -m "$partition" \
            is-dir /Windows/System32 2>/dev/null || true
    )"

    if [[ "$is_windows" == "true" ]]; then
        windows_partition="$partition"
        break
    fi
done

if [[ -z "$windows_partition" ]]; then
    cat >&2 <<MSG
ERROR: Could not identify the Windows C: partition automatically.

The VM disk is readable, but Ubuntu 22.04 libguestfs could not find an NTFS
partition containing /Windows/System32.

Inspect the image manually with:
  sudo env LIBGUESTFS_BACKEND=direct \\
    virt-filesystems -a "$VM_DISK" --all --long -h

Then follow docs/windows-vm.md section 10 to mount the correct partition
explicitly with guestmount -m /dev/sdXN.
MSG
    exit 1
fi

echo "Detected Windows C: partition: $windows_partition"
echo "Mounting $VM_NAME read-only at $VM_MOUNT..."

if ! sudo env LIBGUESTFS_BACKEND=direct \
        guestmount \
        -a "$VM_DISK" \
        -m "$windows_partition" \
        --ro \
        -o allow_other \
        -o "uid=$(id -u)" \
        -o "gid=$(id -g)" \
        "$VM_MOUNT"; then
    cat >&2 <<'MSG'
ERROR: guestmount could not mount the Windows filesystem.
Common causes:
  - Windows hibernation/Fast Startup was not disabled (run: powercfg /h off)
  - BitLocker/Device Encryption is still enabled (run: manage-bde -status C:)
  - Windows was not shut down cleanly
See docs/windows-vm.md section 10 for the Ubuntu 22.04 direct-backend workflow.
MSG
    exit 1
fi

if [[ ! -d "$VM_MOUNT/Windows/System32" ]]; then
    sudo guestunmount "$VM_MOUNT" || true
    echo "ERROR: A filesystem was mounted, but it does not look like the Windows C: drive." >&2
    exit 1
fi

printf 'Mounted read-only: %s (%s) -> %s\n' "$VM_NAME" "$windows_partition" "$VM_MOUNT"
printf 'Note: findmnt may show the outer FUSE transport as rw; guestmount used --ro.\n'
printf 'Set WINDOWS_MOUNT="%s" in inventor.env (the default already matches).\n' "$VM_MOUNT"
printf 'Next: bash scripts/doctor.sh\n'
