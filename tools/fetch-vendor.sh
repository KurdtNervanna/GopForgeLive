#!/usr/bin/env bash
# fetch-vendor.sh — pull GopForge and pre-cache its EnableGop deps into vendor/.
# Run this once on a networked machine before building the USB, so the field
# disk works fully offline.
set -Eeuo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="$HERE/vendor"
GOPFORGE_REPO="${GOPFORGE_REPO:-https://github.com/KurdtNervanna/GopForge.git}"
GOPFORGE_REF="${GOPFORGE_REF:-main}"

mkdir -p "$VENDOR"

if [ -d "$VENDOR/gopforge/.git" ]; then
  echo "» updating vendored GopForge …"
  git -C "$VENDOR/gopforge" fetch --depth 1 origin "$GOPFORGE_REF"
  git -C "$VENDOR/gopforge" checkout -q FETCH_HEAD
else
  echo "» cloning GopForge ($GOPFORGE_REF) …"
  git clone --depth 1 --branch "$GOPFORGE_REF" "$GOPFORGE_REPO" "$VENDOR/gopforge"
fi

# Pre-cache EnableGop.ffs (+ optionally DXEInject) via GopForge's own --fetch.
# DXEInject's host is HTTP-only; GopForge TOFU-pins it. We do NOT redistribute
# DXEInject in this repo (licensing) — this fetch is opt-in.
if [ "${SKIP_FETCH_TOOLS:-0}" != "1" ]; then
  # Cache INTO vendor/gopforge/tools so the .ffs + DXEInject travel with the
  # bundle (install-to-usb copies vendor/gopforge) and are found offline at
  # flash time. --tools-dir makes GopForge's ./tools default absolute, so this
  # works regardless of the CWD the wizard later runs from. Cache both the
  # standard and the direct EnableGop variants.
  GF_TOOLS="$VENDOR/gopforge/tools"
  echo "» caching EnableGop tooling into $GF_TOOLS (standard + direct + DXEInject) …"
  bash "$VENDOR/gopforge/gopforge.sh" --fetch          --tools-dir "$GF_TOOLS" || {
    echo "! gopforge --fetch (standard) failed (network / DXEInject host)." >&2
    echo "  You can fetch at flash time, or drop EnableGop.ffs + DXEInject in $GF_TOOLS." >&2
  }
  bash "$VENDOR/gopforge/gopforge.sh" --fetch --direct --tools-dir "$GF_TOOLS" \
    || echo "! gopforge --fetch (direct variant) failed — direct BootROM injection will need network." >&2
fi

echo "✓ vendor ready at $VENDOR/gopforge"
