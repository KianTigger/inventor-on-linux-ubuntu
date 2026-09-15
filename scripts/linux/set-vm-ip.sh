#!/usr/bin/env bash
# Store the Windows VM's current IPv4 address in .bridge-client.env.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common-vm.sh
source "$SCRIPT_DIR/common-vm.sh"

ENV_FILE="$ROOT/.bridge-client.env"
[[ -f "$ENV_FILE" ]] || {
    echo "ERROR: Missing $ENV_FILE" >&2
    echo "Create it from .bridge-client.env.example and add the Windows bridge token first." >&2
    exit 1
}

if [[ $# -gt 1 ]]; then
    echo "Usage: $0 [IPv4-address]" >&2
    exit 2
fi

if [[ $# -eq 1 ]]; then
    ip="$1"
else
    require_command virsh
    # Prefer the libvirt DHCP lease. It works without qemu-guest-agent.
    ip="$(
        virsh_vm domifaddr "$VM_NAME" --source lease 2>/dev/null \
            | awk '/ipv4/ {sub(/\/.*/, "", $4); print $4; exit}' \
            || true
    )"
fi

if [[ ! "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    echo "ERROR: Could not determine a valid IPv4 address." >&2
    echo "Inside Windows run 'ipconfig', then run:" >&2
    echo "  bash scripts/linux/set-vm-ip.sh <Windows-IPv4>" >&2
    exit 1
fi

python3 - "$ENV_FILE" "$ip" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
ip = sys.argv[2]
lines = path.read_text(encoding="utf-8-sig", errors="replace").splitlines()
out = []
replaced = False
for line in lines:
    stripped = line.strip()
    if stripped.startswith("VM_IP=") or stripped.startswith("# VM_IP="):
        if not replaced:
            out.append(f'VM_IP="{ip}"')
            replaced = True
        continue
    out.append(line)
if not replaced:
    insert_at = 0
    for idx, line in enumerate(out):
        if line.strip().startswith("VM_NAME="):
            insert_at = idx + 1
            break
    out.insert(insert_at, f'VM_IP="{ip}"')
path.write_text("\n".join(out) + "\n", encoding="utf-8")
PY
chmod 600 "$ENV_FILE"
echo "Saved VM_IP=$ip in $ENV_FILE"
echo "Current bridge target: $ip:${INVENTOR_BRIDGE_PORT:-8765}"
