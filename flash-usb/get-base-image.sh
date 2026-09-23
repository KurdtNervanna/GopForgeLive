#!/usr/bin/env bash
# get-base-image.sh — download the latest GRML-FLASH release image (the bootable
# base) into flash-usb/, and convert it to a raw .img when needed. Works on
# Linux/macOS/WSL (needs curl). On plain Windows, download it from the Releases
# page in a browser instead.
#
# GRML-FLASH currently ships a zlib-compressed UDIF .dmg. balenaEtcher can write
# that directly, but the remaster / raw-write paths need a raw .img, so this
# converts it with dmg2img when available.
set -Eeuo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
API="https://api.github.com/repos/Ausdauersportler/GRML-FLASH/releases/latest"

command -v curl >/dev/null 2>&1 || { echo "curl required"; exit 2; }
echo "» querying latest GRML-FLASH release…"
json="$(curl -fsSL "$API")" || { echo "✗ could not reach the GitHub API (network / rate limit)"; exit 1; }

# pick the first image-like asset. NOTE: computed with '|| true' so an empty
# match does not trip 'set -e' before the friendly check below.
url="$(printf '%s\n' "$json" \
  | grep -oE '"browser_download_url": *"[^"]+"' \
  | sed -E 's/.*"(https[^"]+)"/\1/' \
  | grep -iE '\.(dmg|img|img\.gz|img\.xz|iso|zip)$' | head -n1 || true)"
if [ -z "$url" ]; then
  echo "✗ no image asset found on the latest release. Assets present:"
  printf '%s\n' "$json" | grep -oE '"name": *"[^"]+"' | sed -E 's/.*"name": *"([^"]+)"/  - \1/'
  echo "See https://github.com/Ausdauersportler/GRML-FLASH/releases"
  exit 1
fi

out="$HERE/$(basename "$url")"
echo "» downloading $url"
curl -fL --progress-bar -o "$out" "$url"
echo "✓ saved $out"

# Normalise to a raw .img the remaster / raw writers can loop-mount.
case "$out" in
  *.gz)  echo "» decompressing…"; gunzip -kf "$out"; out="${out%.gz}";;
  *.xz)  echo "» decompressing…"; xz -dkf "$out"; out="${out%.xz}";;
  *.zip) echo "» note: unzip $out and use the .img inside.";;
  *.dmg)
    img="${out%.dmg}.img"
    if command -v dmg2img >/dev/null 2>&1; then
      echo "» converting compressed .dmg → raw .img (dmg2img)…"
      dmg2img -i "$out" -o "$img" && out="$img"
    elif command -v hdiutil >/dev/null 2>&1; then
      echo "» converting .dmg → raw .img (hdiutil)…"
      hdiutil convert "$out" -format UDRW -o "${img%.img}" >/dev/null && mv -f "${img%.img}.img" "$img" 2>/dev/null; out="$img"
    else
      echo "! this is a compressed .dmg. To use the remaster / raw-write path, install a converter:"
      echo "    sudo apt-get install -y dmg2img   # Debian/Ubuntu/WSL"
      echo "  then re-run this script."
      echo "! OR just write the .dmg straight to USB with balenaEtcher (no conversion needed)."
      echo "Base image (compressed): $out"
      exit 0
    fi
    ;;
esac

echo "✓ base image ready: $out"
echo "Next:"
echo "  sudo bash tools/remaster-image.sh --img \"$out\" --out flash-usb/gopforge-live.img"
echo "  # then write gopforge-live.img to USB (Windows PowerShell writer or balenaEtcher)"
