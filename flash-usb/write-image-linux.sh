#!/usr/bin/env bash
# write-image-linux.sh — write a bootable image to a USB stick on Linux, then
# (optionally) copy the GopForge-Live bundle onto its FAT data partition.
#
#   sudo ./write-image-linux.sh <image.img> [/dev/sdX] [--no-install]
#
# <image.img> is the GRML-FLASH release image (see flash-usb/README.md for how
# to get it). The bundle copied is this checkout (bin/, catalog/, docs/, roms/,
# vendor/gopforge). UNTESTED — writing to the wrong device destroys data.
set -Eeuo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
IMG="${1:-}"; DEV="${2:-}"; DO_INSTALL=1
for a in "$@"; do [ "$a" = "--no-install" ] && DO_INSTALL=0; done
[ -n "$IMG" ] && [ -f "$IMG" ] || { echo "usage: sudo $0 <image.img> [/dev/sdX] [--no-install]"; exit 2; }
[ "$(id -u)" = 0 ] || { echo "run as root (sudo)."; exit 2; }

echo "== removable disks =="
lsblk -dpno NAME,SIZE,TRAN,RM,MODEL | awk '$4==1 || $3=="usb"{print "  "$0}'
echo "(full list:)"; lsblk -dpno NAME,SIZE,TYPE,TRAN,RM,MODEL | sed 's/^/  /'

if [ -z "$DEV" ]; then read -r -p "target device (e.g. /dev/sdb): " DEV; fi
[ -b "$DEV" ] || { echo "not a block device: $DEV"; exit 2; }

# Safety gates
rm_flag="$(lsblk -dno RM "$DEV" 2>/dev/null | tr -d ' ')"
tran="$(lsblk -dno TRAN "$DEV" 2>/dev/null | tr -d ' ')"
if lsblk -no MOUNTPOINT "$DEV" | grep -qxE '/|/boot|/boot/efi'; then
  echo "REFUSING: $DEV hosts a system mountpoint."; exit 3
fi
if [ "$rm_flag" != 1 ] && [ "$tran" != usb ]; then
  echo "WARNING: $DEV is not removable/USB (RM=$rm_flag TRAN=$tran)."
  read -r -p "type FORCE to continue anyway: " f; [ "$f" = FORCE ] || exit 3
fi

size="$(lsblk -dno SIZE "$DEV")"; model="$(lsblk -dno MODEL "$DEV" | xargs)"
echo; echo "About to ERASE and write:"
echo "  image : $IMG"
echo "  target: $DEV  ($size  $model)"
read -r -p "type the device path again to confirm ($DEV): " c
[ "$c" = "$DEV" ] || { echo "mismatch — aborted."; exit 3; }

# Unmount any existing partitions
for p in "${DEV}"?* ; do mountpoint -q "$p" 2>/dev/null && umount "$p" || true; done
umount "${DEV}"?* 2>/dev/null || true

echo "» writing (dd)…"
dd if="$IMG" of="$DEV" bs=4M conv=fsync status=progress
sync; partprobe "$DEV" 2>/dev/null || true
echo "✓ image written"

if [ "$DO_INSTALL" = 1 ]; then
  echo "» locating FAT data partition to install the bundle…"
  sleep 2
  local_mnt="$(mktemp -d)"; installed=0
  for p in $(lsblk -lnpo NAME,FSTYPE "$DEV" | awk '$2=="vfat"||$2=="fat32"||$2=="exfat"{print $1}'); do
    if mount "$p" "$local_mnt" 2>/dev/null; then
      "$REPO/tools/install-to-usb.sh" "$local_mnt" && installed=1
      sync; umount "$local_mnt"; break
    fi
  done
  rmdir "$local_mnt" 2>/dev/null || true
  [ "$installed" = 1 ] && echo "✓ bundle installed onto the USB" \
    || echo "! could not auto-mount a FAT partition; mount it and run tools/install-to-usb.sh manually"
fi
echo "Done. Eject safely and boot the target Mac from this USB."
