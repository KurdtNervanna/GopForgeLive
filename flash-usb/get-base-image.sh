#!/usr/bin/env bash
# get-base-image.sh — download the latest GRML-FLASH release image (the bootable
# base) into flash-usb/. Works on Linux/macOS/WSL (needs curl). On plain Windows,
# download it from the Releases page in a browser instead.
set -Eeuo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
API="https://api.github.com/repos/Ausdauersportler/GRML-FLASH/releases/latest"

command -v curl >/dev/null 2>&1 || { echo "curl required"; exit 2; }
echo "» querying latest GRML-FLASH release…"
json="$(curl -fsSL "$API")"
# pick the first image-like asset (.img, .img.gz, .img.xz, .iso, or .zip)
url="$(printf '%s\n' "$json" \
  | grep -oE '"browser_download_url": *"[^"]+"' \
  | sed -E 's/.*"(https[^"]+)"/\1/' \
  | grep -iE '\.(img|img\.gz|img\.xz|iso|zip)$' | head -n1)"
[ -n "$url" ] || { echo "could not find an image asset; see https://github.com/Ausdauersportler/GRML-FLASH/releases"; exit 1; }

out="$HERE/$(basename "$url")"
echo "» downloading $url"
curl -fL --progress-bar -o "$out" "$url"
echo "✓ saved $out"
case "$out" in
  *.gz) echo "» decompressing…"; gunzip -kf "$out"; out="${out%.gz}";;
  *.xz) echo "» decompressing…"; xz -dkf "$out"; out="${out%.xz}";;
  *.zip) echo "note: unzip $out and use the .img inside.";;
esac
echo "Base image ready: $out"
echo "Next: sudo ./write-image-linux.sh \"$out\" /dev/sdX   (or the macOS/Windows writer)"
