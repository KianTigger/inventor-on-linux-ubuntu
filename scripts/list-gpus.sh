#!/usr/bin/env bash
# Show Vulkan device names and UUIDs in a form suitable for inventor.env.
set -euo pipefail

if ! command -v vulkaninfo >/dev/null 2>&1; then
    echo "ERROR: vulkaninfo is missing. Run scripts/phase0-setup.sh." >&2
    exit 1
fi

summary="$(vulkaninfo --summary 2>&1)"
awk '
    /^GPU[0-9]+:/ {gpu=$0; name=""; uuid=""}
    /deviceName[[:space:]]*=/ {sub(/^[^=]*=[[:space:]]*/, ""); name=$0}
    /deviceUUID[[:space:]]*=/ {
        sub(/^[^=]*=[[:space:]]*/, ""); uuid=$0; gsub(/-/, "", uuid)
        printf "%s\n  Name: %s\n  DXVK_FILTER_DEVICE_UUID=\"%s\"\n\n", gpu, name, uuid
    }
' <<< "$summary"

if command -v nvidia-smi >/dev/null 2>&1; then
    echo "NVIDIA utilization / PCI mapping:"
    nvidia-smi --query-gpu=index,pci.bus_id,name,memory.used,memory.total,utilization.gpu \
        --format=csv,noheader
fi
