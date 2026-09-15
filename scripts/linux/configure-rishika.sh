#!/usr/bin/env bash
set -euo pipefail
if [[ $# -ne 1 ]]; then
    echo "Usage: $0 /path/to/Rishika" >&2
    exit 2
fi
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RISHIKA="$(readlink -f "$1")"
[[ -f "$RISHIKA/.env" ]] || { echo "ERROR: $RISHIKA/.env does not exist" >&2; exit 1; }
# shellcheck disable=SC1091
source "$ROOT/.bridge-client.env"
python3 - "$RISHIKA/.env" "$INVENTOR_BRIDGE_TOKEN" "${VM_NAME:-inventor-win11}" "${INVENTOR_BRIDGE_PORT:-8765}" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
values = {
    "INVENTOR_BACKEND": "remote",
    "INVENTOR_BRIDGE_URL": "auto",
    "INVENTOR_BRIDGE_TOKEN": sys.argv[2],
    "INVENTOR_VM_NAME": sys.argv[3],
    "INVENTOR_BRIDGE_PORT": sys.argv[4],
}
lines = path.read_text(encoding="utf-8-sig", errors="replace").splitlines()
keys = set(values)
out = []
seen = set()
for line in lines:
    stripped = line.strip()
    if "=" in stripped and not stripped.startswith("#"):
        key = stripped.split("=", 1)[0].strip()
        if key in values:
            out.append(f"{key}={values[key]}")
            seen.add(key)
            continue
    out.append(line)
if out and out[-1].strip():
    out.append("")
out.append("# Inventor VM bridge")
for key, value in values.items():
    if key not in seen:
        out.append(f"{key}={value}")
path.write_text("\n".join(out) + "\n", encoding="utf-8")
PY
echo "Updated $RISHIKA/.env for remote Inventor COM through the Windows VM."
