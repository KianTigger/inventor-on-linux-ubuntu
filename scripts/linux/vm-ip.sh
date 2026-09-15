#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common-vm.sh
source "$SCRIPT_DIR/common-vm.sh"
[[ -f "$ROOT/.bridge-client.env" ]] && source "$ROOT/.bridge-client.env"

if [[ -n "${VM_IP:-}" ]]; then
    printf '%s\n' "$VM_IP"
    exit 0
fi

require_command virsh

for source in agent lease arp; do
    ip="$(virsh_vm domifaddr "$VM_NAME" --source "$source" 2>/dev/null | awk '/ipv4/ {sub(/\/.*/, "", $4); print $4; exit}')"
    if [[ -n "$ip" ]]; then
        printf '%s\n' "$ip"
        exit 0
    fi
done

mac="$(virsh_vm domiflist "$VM_NAME" 2>/dev/null | awk '/network|bridge/ {print $5; exit}')"
if [[ -n "$mac" ]]; then
    while read -r network; do
        [[ -z "$network" ]] && continue
        ip="$(virsh_vm net-dhcp-leases "$network" 2>/dev/null | awk -v mac="$mac" 'tolower($3)==tolower(mac) && /ipv4/ {sub(/\/.*/, "", $5); print $5; exit}')"
        if [[ -n "$ip" ]]; then
            printf '%s\n' "$ip"
            exit 0
        fi
    done < <(virsh_vm net-list --name --all 2>/dev/null)
fi

echo "ERROR: Could not discover an IPv4 address for libvirt domain '$VM_NAME'." >&2
echo "Inside Windows run 'ipconfig', then set VM_IP in windows-vm.env if needed." >&2
exit 1
