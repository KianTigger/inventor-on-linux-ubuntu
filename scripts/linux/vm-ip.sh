#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common-vm.sh
source "$SCRIPT_DIR/common-vm.sh"
[[ -f "$ROOT/.bridge-client.env" ]] && source "$ROOT/.bridge-client.env"

# VM_IP in .bridge-client.env is the preferred and most deterministic source.
if [[ -n "${VM_IP:-}" ]]; then
    printf '%s\n' "$VM_IP"
    exit 0
fi

require_command virsh

# Fall back to discovery. Lease is tried first because it does not require the
# QEMU guest agent. Every failed source is explicitly tolerated so `set -e` /
# `pipefail` cannot abort the script before the next source is attempted.
for source in lease agent arp; do
    ip="$(
        virsh_vm domifaddr "$VM_NAME" --source "$source" 2>/dev/null \
            | awk '/ipv4/ {sub(/\/.*/, "", $4); print $4; exit}' \
            || true
    )"
    if [[ -n "$ip" ]]; then
        printf '%s\n' "$ip"
        exit 0
    fi
done

# Last fallback: look up the interface MAC in libvirt DHCP leases.
mac="$(virsh_vm domiflist "$VM_NAME" 2>/dev/null | awk '/network|bridge/ {print $5; exit}' || true)"
if [[ -n "$mac" ]]; then
    while read -r network; do
        [[ -z "$network" ]] && continue
        ip="$(
            virsh_vm net-dhcp-leases "$network" 2>/dev/null \
                | awk -v mac="$mac" 'tolower($3)==tolower(mac) && /ipv4/ {sub(/\/.*/, "", $5); print $5; exit}' \
                || true
        )"
        if [[ -n "$ip" ]]; then
            printf '%s\n' "$ip"
            exit 0
        fi
    done < <(virsh_vm net-list --name --all 2>/dev/null || true)
fi

echo "ERROR: Could not determine an IPv4 address for libvirt domain '$VM_NAME'." >&2
echo "Run 'ipconfig' inside Windows (or 'virsh --connect $LIBVIRT_URI domifaddr $VM_NAME --source lease')" >&2
echo "and set VM_IP in $ROOT/.bridge-client.env." >&2
exit 1
