#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

sudo apt update
sudo apt install -y \
    cpu-checker \
    qemu-kvm \
    qemu-utils \
    libvirt-daemon-system \
    libvirt-clients \
    virtinst \
    virt-viewer \
    ovmf \
    swtpm \
    swtpm-tools \
    libosinfo-bin \
    curl \
    unzip

sudo systemctl enable --now libvirtd

# Add the invoking user, not root, to the VM management groups.
sudo usermod -aG libvirt,kvm "$USER"

# Make the default NAT network persistent when it exists.
if sudo virsh --connect qemu:///system net-info default >/dev/null 2>&1; then
    sudo virsh --connect qemu:///system net-autostart default >/dev/null
    if ! sudo virsh --connect qemu:///system net-info default | grep -q 'Active:.*yes'; then
        sudo virsh --connect qemu:///system net-start default >/dev/null
    fi
fi

if command -v kvm-ok >/dev/null 2>&1; then
    echo
    kvm-ok || true
fi

echo
echo "Ubuntu virtualization packages are installed."
echo "IMPORTANT: log out of the Ubuntu shell/session and log back in before running create-windows-vm.sh"
echo "so the new libvirt/kvm group memberships take effect."
echo "Then copy windows-vm.env.example to windows-vm.env and edit it."
