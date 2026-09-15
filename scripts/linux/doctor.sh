#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common-vm.sh
source "$SCRIPT_DIR/common-vm.sh"

failures=0
checks=0
ok() { echo "[ OK ] $*"; }
fail() { echo "[FAIL] $*"; failures=$((failures+1)); }
check_cmd() { checks=$((checks+1)); command -v "$1" >/dev/null 2>&1 && ok "$1 installed" || fail "$1 missing"; }

for cmd in virsh virt-install curl; do check_cmd "$cmd"; done
checks=$((checks+1))
[[ -e /dev/kvm ]] && ok "/dev/kvm present" || fail "/dev/kvm missing"
checks=$((checks+1))
[[ -f "$ROOT/windows-vm.env" ]] && ok "windows-vm.env configured" || fail "windows-vm.env missing"
checks=$((checks+1))
[[ -f "$ROOT/.bridge-client.env" ]] && ok ".bridge-client.env present" || fail ".bridge-client.env missing"

if command -v virsh >/dev/null 2>&1; then
    checks=$((checks+1))
    if vm_exists; then
        ok "VM '$VM_NAME' exists"
        echo "       state: $(vm_state)"
    else
        fail "VM '$VM_NAME' does not exist"
    fi
fi

echo
echo "$checks checks, $failures failure(s)."
exit "$failures"
