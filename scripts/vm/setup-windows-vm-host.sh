#!/usr/bin/env bash
# Install Ubuntu 22.04 KVM/libvirt prerequisites for the Windows staging VM.
set -euo pipefail
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
# shellcheck source=common-vm.sh
source "$SCRIPT_DIR/common-vm.sh"

if [[ $EUID -eq 0 ]]; then
    echo "ERROR: Run this as your normal Linux account, not with sudo." >&2
    echo "       The script invokes sudo for system changes." >&2
    exit 1
fi

if [[ ! -r /etc/os-release ]]; then
    echo "ERROR: /etc/os-release is unavailable." >&2
    exit 1
fi
# shellcheck disable=SC1091
source /etc/os-release
if [[ "${ID:-}" != ubuntu || "${VERSION_ID:-}" != 22.04 ]]; then
    echo "ERROR: This VM setup is written for Ubuntu 22.04; found ${PRETTY_NAME:-unknown}." >&2
    exit 1
fi
if [[ "$(uname -m)" != x86_64 ]]; then
    echo "ERROR: x86_64 is required for the Windows 11/Inventor staging VM." >&2
    exit 1
fi

sudo apt-get update
sudo apt-get install -y software-properties-common
sudo add-apt-repository -y universe
sudo apt-get update
sudo apt-get install -y \
    qemu-kvm \
    libvirt-daemon-system \
    libvirt-clients \
    virtinst \
    ovmf \
    swtpm \
    swtpm-tools \
    libguestfs-tools \
    cpu-checker \
    osinfo-db \
    curl

sudo systemctl enable --now libvirtd

# Grant the normal account access to qemu:///system and /dev/kvm.
sudo adduser "$USER" libvirt >/dev/null || true
sudo adduser "$USER" kvm >/dev/null || true

if [[ ! -e /dev/kvm ]]; then
    echo "ERROR: /dev/kvm is missing. Hardware virtualization may be disabled in firmware" >&2
    echo "       or unavailable to this host." >&2
    exit 1
fi

if command -v kvm-ok >/dev/null 2>&1; then
    sudo kvm-ok || true
fi

# Ensure the standard NAT network is defined and starts automatically.
if ! sudo virsh --connect qemu:///system net-info default >/dev/null 2>&1; then
    if [[ -f /usr/share/libvirt/networks/default.xml ]]; then
        sudo virsh --connect qemu:///system net-define /usr/share/libvirt/networks/default.xml >/dev/null
    else
        echo "ERROR: libvirt's default NAT network is not defined and its template is missing." >&2
        exit 1
    fi
fi
sudo virsh --connect qemu:///system net-autostart default >/dev/null
if [[ "$(sudo virsh --connect qemu:///system net-info default | awk '/Active:/ {print $2}')" != yes ]]; then
    sudo virsh --connect qemu:///system net-start default >/dev/null
fi

for f in /usr/share/OVMF/OVMF_CODE_4M.ms.fd /usr/share/OVMF/OVMF_VARS_4M.ms.fd; do
    if [[ ! -r "$f" ]]; then
        echo "ERROR: Required Secure Boot OVMF image missing: $f" >&2
        exit 1
    fi
done

# Microsoft transitioned UEFI signing to the 2023 CAs on 2026-06-26.
# Ubuntu's Jammy 22.04.6 OVMF SRU expands the default key enrollment with
# those 2023 keys. Require that update so current Windows 11 media can boot
# under Secure Boot instead of silently creating a VM with stale firmware.
ovmf_version="$(dpkg-query -W -f='${Version}' ovmf 2>/dev/null || true)"
minimum_ovmf='2022.02-3ubuntu0.22.04.6'
if [[ -z "$ovmf_version" ]] || dpkg --compare-versions "$ovmf_version" lt "$minimum_ovmf"; then
    echo "ERROR: OVMF $minimum_ovmf or newer is required; found ${ovmf_version:-none}." >&2
    echo "       Ensure jammy-updates is enabled and run sudo apt update && sudo apt upgrade ovmf." >&2
    exit 1
fi

printf '\nKVM/libvirt host setup is complete.\n'
printf 'IMPORTANT: log out completely and log back in before running create-windows-vm.sh.\n'
printf 'This activates your new libvirt and kvm group membership.\n'
