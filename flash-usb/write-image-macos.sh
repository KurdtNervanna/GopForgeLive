#!/usr/bin/env bash
# write-image-macos.sh — write a bootable image to a USB stick on macOS, then
# (optionally) copy the GopForge-Live bundle onto its FAT data partition.
#
#   sudo ./write-image-macos.sh <image.img> [/dev/diskN] [--no-install]
#
# <image.img> is the GRML-FLASH release image (see flash-usb/README.md).
# UNTESTED — writing to the wrong disk destroys data.
set -Eeuo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
IMG="${1:-}"; DISK="${2:-}"; DO_INSTALL=1
for a in "$@"; do [ "$a" = "--no-install" ] && DO_INSTALL=0; done
[ -n "$IMG" ] && [ -f "$IMG" ] || { echo "usage: sudo $0 <image.img> [/dev/diskN] [--no-install]"; exit 2; }
[ "$(id -u)" = 0 ] || { echo "run with sudo."; exit 2; }

echo "== external physical disks =="
diskutil list external physical || true

if [ -z "$DISK" ]; then read -r -p "target disk (e.g. /dev/disk4): " DISK; fi
[ -e "$DISK" ] || { echo "no such disk: $DISK"; exit 2; }

# Safety: must be external + not the internal/boot disk.
internal="$(diskutil info "$DISK" 2>/dev/null | awk -F': *' '/Internal/{print $2; exit}' | xargs)"
if [ "$internal" = "Yes" ]; then echo "REFUSING: $DISK is an internal disk."; exit 3; fi
name="$(diskutil info "$DISK" 2>/dev/null | awk -F': *' '/Device \/ Media Name/{print $2; exit}')"
size="$(diskutil info "$DISK" 2>/dev/null | awk -F': *' '/Disk Size/{print $2; exit}')"

echo; echo "About to ERASE and write:"
echo "  image : $IMG"
echo "  target: $DISK  ($size  $name)"
read -r -p "type the disk id again to confirm ($DISK): " c
[ "$c" = "$DISK" ] || { echo "mismatch — aborted."; exit 3; }

echo "» unmounting $DISK…"
diskutil unmountDisk "$DISK"

# /dev/rdiskN is the raw (faster) node.
RDISK="${DISK/\/dev\/disk//dev/rdisk}"
echo "» writing (dd) to $RDISK…"
dd if="$IMG" of="$RDISK" bs=4m
sync
echo "✓ image written"

if [ "$DO_INSTALL" = 1 ]; then
  echo "» remounting to install the bundle…"
  diskutil mountDisk "$DISK" 2>/dev/null || true
  sleep 2
  # Find a FAT volume that belongs to this disk.
  installed=0
  while IFS= read -r vol; do
    [ -d "$vol" ] || continue
    if "$REPO/tools/install-to-usb.sh" "$vol"; then installed=1; sync; break; fi
  done < <(diskutil list "$DISK" | awk '/Microsoft Basic Data|DOS_FAT|Windows_FAT|EFI/{print}' >/dev/null 2>&1; ls -d /Volumes/* 2>/dev/null)
  [ "$installed" = 1 ] && echo "✓ bundle installed" \
    || echo "! could not auto-locate the FAT volume; open it in Finder and run tools/install-to-usb.sh <volume> manually"
  diskutil eject "$DISK" 2>/dev/null || true
fi
echo "Done. Boot the target Mac from this USB (hold ⌥ Option at power-on)."
