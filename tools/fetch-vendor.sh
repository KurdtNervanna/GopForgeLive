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
  echo "» pre-fetching EnableGop tooling via gopforge --fetch …"
  bash "$VENDOR/gopforge/gopforge.sh" --fetch || {
    echo "! gopforge --fetch failed (network / DXEInject host). You can still" >&2
    echo "  fetch at flash time, or drop EnableGop.ffs + DXEInject in place." >&2
  }
fi

echo "✓ vendor ready at $VENDOR/gopforge"
