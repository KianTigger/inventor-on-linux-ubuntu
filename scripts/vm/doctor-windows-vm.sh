#!/usr/bin/env bash
# Non-destructive preflight/status report for the Windows staging VM workflow.
set -u
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
# shellcheck source=common-vm.sh
source "$SCRIPT_DIR/common-vm.sh"

failures=0
warnings=0
ok()   { printf 'OK   %s\n' "$*"; }
warn() { printf 'WARN %s\n' "$*"; warnings=$((warnings+1)); }
fail() { printf 'FAIL %s\n' "$*"; failures=$((failures+1)); }

printf '=== Windows staging VM doctor ===\n'
printf 'Config: %s\n\n' "$VM_CONFIG_FILE"

if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    [[ "${ID:-}" == ubuntu && "${VERSION_ID:-}" == 22.04 ]] && ok "OS: ${PRETTY_NAME:-Ubuntu 22.04}" || fail "Expected Ubuntu 22.04; found ${PRETTY_NAME:-unknown}"
else
    fail "/etc/os-release unavailable"
fi

[[ "$(uname -m)" == x86_64 ]] && ok "Architecture: x86_64" || fail "x86_64 required; found $(uname -m)"
[[ -e /dev/kvm ]] && ok "/dev/kvm available" || fail "/dev/kvm missing"

for cmd in virsh virt-install swtpm guestmount guestunmount; do
    command -v "$cmd" >/dev/null 2>&1 && ok "$cmd available" || fail "$cmd missing (run setup-windows-vm-host.sh)"
done

if id -nG | tr ' ' '\n' | grep -qx libvirt; then ok "Current login has libvirt group"; else warn "Current login lacks libvirt group; log out/in after host setup"; fi
if id -nG | tr ' ' '\n' | grep -qx kvm; then ok "Current login has kvm group"; else warn "Current login lacks kvm group; log out/in after host setup"; fi

ovmf_version="$(dpkg-query -W -f='${Version}' ovmf 2>/dev/null || true)"
minimum_ovmf='2022.02-3ubuntu0.22.04.6'
if [[ -n "$ovmf_version" ]] && ! dpkg --compare-versions "$ovmf_version" lt "$minimum_ovmf"; then
    ok "OVMF: $ovmf_version (includes Jammy Microsoft 2023 CA update)"
else
    fail "OVMF $minimum_ovmf+ required; found ${ovmf_version:-none}"
fi
[[ -r "$VM_UEFI_CODE" && -r "$VM_UEFI_VARS" ]] && ok "Secure Boot OVMF images present" || fail "Configured OVMF firmware images missing"

if virsh list --all >/dev/null 2>&1; then
    ok "System libvirt accessible"
    if virsh net-info default >/tmp/inventor-vm-net.txt 2>&1; then
        net_active="$(awk '/Active:/ {print $2}' /tmp/inventor-vm-net.txt)"
        [[ "$net_active" == yes ]] && ok "libvirt default NAT network active" || fail "libvirt default NAT network is not active"
    else
        fail "libvirt default NAT network missing"
    fi
else
    fail "Cannot access qemu:///system as $(id -un)"
fi

[[ -f "$VM_CONFIG_FILE" ]] && ok "windows-vm.env exists" || warn "windows-vm.env missing; copy windows-vm.env.example before creating the VM"

if vm_domain_exists; then
    state="$(vm_state)"
    ok "VM '$VM_NAME' exists; state: $state"
    xml="$(virsh dumpxml "$VM_NAME" 2>/dev/null || true)"
    grep -q "<tpm model='tpm-crb'>" <<<"$xml" && grep -q "version='2.0'" <<<"$xml" && ok "VM has emulated TPM 2.0" || warn "Could not verify tpm-crb/TPM 2.0 in domain XML"
    grep -q "secure='yes'" <<<"$xml" && ok "Domain XML marks UEFI loader Secure Boot enabled" || warn "Could not verify loader secure='yes' in domain XML"
else
    warn "VM '$VM_NAME' has not been created yet"
    if [[ -n "$WINDOWS_ISO_SOURCE" && -r "$WINDOWS_ISO_SOURCE" ]]; then ok "Windows ISO source readable: $WINDOWS_ISO_SOURCE"; else warn "WINDOWS_ISO_SOURCE not readable yet"; fi
fi

if command -v mountpoint >/dev/null 2>&1 && mountpoint -q "$VM_MOUNT"; then
    ok "Windows source currently mounted: $VM_MOUNT"
    [[ -d "$VM_MOUNT/Windows/System32" ]] && ok "Mounted tree contains Windows/System32" || fail "Mounted tree does not look like Windows C:"
    if vm_domain_exists && [[ "$(vm_state)" != "shut off" ]]; then fail "VM is running while source mount is active; shut it down/unmount immediately"; fi
else
    warn "Windows VM is not mounted at $VM_MOUNT"
fi

printf '\nResult: %d failure(s), %d warning(s)\n' "$failures" "$warnings"
(( failures == 0 ))
