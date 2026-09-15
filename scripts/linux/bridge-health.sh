#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common-vm.sh
source "$SCRIPT_DIR/common-vm.sh"
[[ -f "$ROOT/.bridge-client.env" ]] || { echo "ERROR: Missing $ROOT/.bridge-client.env" >&2; exit 1; }
# shellcheck disable=SC1091
source "$ROOT/.bridge-client.env"

PORT="${INVENTOR_BRIDGE_PORT:-8765}"
TOKEN="${INVENTOR_BRIDGE_TOKEN:?INVENTOR_BRIDGE_TOKEN is required}"
IP="${VM_IP:-}"
if [[ -z "$IP" ]]; then
    IP="$($ROOT/scripts/linux/vm-ip.sh)"
fi

echo "Bridge: http://$IP:$PORT"
curl -fsS --max-time 5 "http://$IP:$PORT/health"; echo
curl -fsS --max-time 90 \
  -H "X-Inventor-Bridge-Token: $TOKEN" \
  "http://$IP:$PORT/v1/status"; echo
