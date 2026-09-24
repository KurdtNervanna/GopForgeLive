#!/usr/bin/env bash
# run-gui-dev.sh — run the GopForge-Live GUI against SIMULATED hardware.
# Safe on any Linux/WSL box: no root needed, nothing real is read or written.
#
#   dev/run-gui-dev.sh [model] [gpus] [port]
#     model  MacPro5,1 (default) | MacPro4,1 | iMac12,2 | iMac10,1 | iMac9,1 | PC
#     gpus   vega64 (default) | rx580 | wx4150 | m6100 | gtx680 | none | a,b list
#   Extra knobs: GFL_MOCK_FAIL=dump|write|backup|flash  GFL_MOCK_PATCHED=1  GFL_MOCK_FAST=1
# Then open http://localhost:<port>/ in a browser.
set -euo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export GFL_MOCK=1
export GFL_MOCK_MODEL="${1:-${GFL_MOCK_MODEL:-MacPro5,1}}"
export GFL_MOCK_GPU="${2:-${GFL_MOCK_GPU:-vega64}}"
PORT="${3:-${PORT:-8765}}"
chmod +x "$HERE"/dev/mock/bin/* "$HERE"/bin/gfl-api 2>/dev/null || true
export PATH="$HERE/dev/mock/bin:$PATH"
export GFL_MEDIUM="$HERE/dev/mock/usb"              # stands in for the USB stick
mkdir -p "$GFL_MEDIUM/flash/video"
rm -f "$GFL_MEDIUM"/.mock-chip.rom*                 # each session starts with a factory chip
export GFL_AMDVBFLASH="$HERE/dev/mock/bin/amdvbflash" GFL_NVFLASH="$HERE/dev/mock/bin/nvflash_linux"
if ! command -v jq >/dev/null 2>&1; then
  mkdir -p "$HERE/dev/.cache"
  [ -x "$HERE/dev/.cache/jq" ] || curl -fsSL -o "$HERE/dev/.cache/jq" \
      https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64
  chmod +x "$HERE/dev/.cache/jq"; export PATH="$HERE/dev/.cache:$PATH"
fi
echo "» mock: $GFL_MOCK_MODEL with GPU(s) $GFL_MOCK_GPU — http://localhost:$PORT/"
exec python3 "$HERE/gui/server.py" --port "$PORT" --no-token
