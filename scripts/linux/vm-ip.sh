#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[[ -f "$ROOT/windows-vm.env" ]] && source "$ROOT/windows-vm.env"
[[ -f "$ROOT/.bridge-client.env" ]] && source "$ROOT/.bridge-client.env"
VM_NAME="${VM_NAME:-inventor-win11}"

if [[ -n "${VM_IP:-}" ]]; then
    printf '%s\n' "$VM_IP"
    exit 0
fi

command -v virsh >/dev/null 2>&1 || { echo "ERROR: virsh is not installed or not in PATH." >&2; exit 1; }

for source in agent lease arp; do
    ip="$(virsh domifaddr "$VM_NAME" --source "$source" 2>/dev/null | awk '/ipv4/ {sub(/\/.*/, "", $4); print $4; exit}')"
    if [[ -n "$ip" ]]; then
        printf '%s\n' "$ip"
        exit 0
    fi
done

mac="$(virsh domiflist "$VM_NAME" 2>/dev/null | awk '/network|bridge/ {print $5; exit}')"
if [[ -n "$mac" ]]; then
    while read -r network; do
        [[ -z "$network" ]] && continue
        ip="$(virsh net-dhcp-leases "$network" 2>/dev/null | awk -v mac="$mac" 'tolower($3)==tolower(mac) && /ipv4/ {sub(/\/.*/, "", $5); print $5; exit}')"
        if [[ -n "$ip" ]]; then
            printf '%s\n' "$ip"
            exit 0
        fi
    done < <(virsh net-list --name --all 2>/dev/null)
fi

echo "ERROR: Could not discover an IPv4 address for libvirt domain '$VM_NAME'." >&2
echo "Set VM_IP in windows-vm.env after checking the address inside Windows with ipconfig." >&2
exit 1
