#!/usr/bin/env bash
# make-iso.sh — turn the remastered USB image into a bootable DVD image (.iso),
# and optionally a .dmg of the same disc for burning from macOS.
#
#   sudo ./tools/make-iso.sh --img gopforge-live.img --out gopforge-live.iso [--dmg gopforge-live.dmg]
#
# The disc carries exactly the files of the USB image's FAT partition (GRML's
# kernel, initrd, base squashfs, our zz-gopforge module and GRUB) and boots through
# GRML's own EFI GRUB from an El Torito EFI image — the same layout GRML's official
# ISOs use on Macs. EFI only: every Mac GopForge-Live supports boots EFI.
#
# Differences from the USB image, all in the boot config:
#   * its own bootid, so a GopForge-Live USB plugged in at boot can't be picked
#     as the live medium instead of the disc,
#   * no `persistence` (nothing on a disc can be written; files go to RAM until
#     "Save to USB" — see bin/lib/storage.sh), plus gfl.media=dvd for the log.
#
# The result is ~1 GB, so it needs a DVD (a 700 MB CD is too small).
# Needs (Linux, root): losetup, mount, rsync, xorriso, mkfs.vfat (dosfstools),
# mtools. --dmg also needs `dmg` from libdmg-hfsplus (tools/build-release.sh builds it).
set -Eeuo pipefail

IMG=""; OUT=""; DMG=""; VOLID="GOPFORGE_LIVE"
while [ $# -gt 0 ]; do
  case "$1" in
    --img) IMG="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    --dmg) DMG="$2"; shift 2;;
    --volid) VOLID="$2"; shift 2;;
    -h|--help) grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "unknown arg: $1"; exit 2;;
  esac
done

die(){ echo "✗ $*" >&2; exit 1; }
say(){ printf '\033[36m» %s\033[0m\n' "$*"; }
ok(){  printf '\033[32m✓ %s\033[0m\n' "$*"; }

[ "$(id -u)" = 0 ] || die "run as root (sudo) — the image is loop-mounted"
[ -n "$IMG" ] && [ -f "$IMG" ] || die "usage: sudo $0 --img <remastered.img> --out <out.iso> [--dmg <out.dmg>]"
OUT="${OUT:-${IMG%.img}.iso}"
for t in losetup mount rsync xorriso mkfs.vfat mmd mcopy; do command -v "$t" >/dev/null 2>&1 || die "missing tool: $t"; done
[ -z "$DMG" ] || command -v dmg >/dev/null 2>&1 || die "--dmg needs the 'dmg' tool from libdmg-hfsplus"

MNT=""; LOOP=""; STAGE=""
cleanup() {
  set +e
  [ -n "$MNT" ] && { umount "$MNT" 2>/dev/null; rmdir "$MNT" 2>/dev/null; }
  [ -n "$LOOP" ] && losetup -d "$LOOP" 2>/dev/null
  [ -n "$STAGE" ] && rm -rf "$STAGE"
}
trap cleanup EXIT

say "mounting $IMG (read-only)"
LOOP="$(losetup -fP --show -r "$IMG")"; sleep 1
MNT="$(mktemp -d)"
if ! { [ -b "${LOOP}p1" ] && mount -o ro "${LOOP}p1" "$MNT" 2>/dev/null; }; then
  pstart="$(sgdisk -i 1 "$IMG" 2>/dev/null | awk -F'[ :]+' '/First sector/{print $3}')"
  mount -o ro,offset=$(( ${pstart:-2048} * 512 )) "$IMG" "$MNT" || die "couldn't mount the image's FAT partition"
fi
[ -f "$MNT/efi/boot/bootx64.efi" ] || die "no efi/boot/bootx64.efi — is this a GRML-FLASH image?"   # FAT: case-insensitive
ls "$MNT"/live/*/zz-gopforge.squashfs >/dev/null 2>&1 || die "no zz-gopforge.squashfs — remaster the image first (tools/remaster-image.sh)"

STAGE="$(mktemp -d "${TMPDIR:-/var/tmp}/gfl-iso.XXXXXX")"
say "copying the disc's files"
# Leave out macOS/Windows litter and anything a user may have put on the stick.
rsync -a --exclude '._*' --exclude '.DS_Store' --exclude '.Spotlight-V100' --exclude '.fseventsd' \
  --exclude '.Trashes' --exclude 'System Volume Information' --exclude '/gopforge-live/' \
  --exclude '/templates.zip' --exclude '/gopforge-plain' --exclude '/gopforge-tui' "$MNT/" "$STAGE/"
umount "$MNT"; rmdir "$MNT"; MNT=""
losetup -d "$LOOP"; LOOP=""

# --- boot config ----------------------------------------------------------------
old_id="$(tr -d ' \r\n' <"$STAGE/conf/bootid.txt" 2>/dev/null || true)"
[ -n "$old_id" ] || die "conf/bootid.txt missing — not a GRML-FLASH layout"
new_id="$(cat /proc/sys/kernel/random/uuid)"
printf '%s' "$new_id" >"$STAGE/conf/bootid.txt"
n=0
for f in "$STAGE"/boot/grub/*.cfg "$STAGE"/boot/syslinux/*.cfg; do
  [ -f "$f" ] || continue
  grep -q 'boot=live' "$f" || continue
  sed -i -E "/boot=live/{ s/bootid=$old_id/bootid=$new_id/g; s/[[:space:]]persistence([[:space:]]|$)/\1/g; /gfl\.media=/! s/[[:space:]]*$/ gfl.media=dvd/ }" "$f"
  n=$((n+1))
done
[ "$n" -gt 0 ] || die "no live-boot entries found in boot/grub or boot/syslinux"
grep -rq "bootid=$old_id" "$STAGE/boot" 2>/dev/null && die "old bootid still referenced in the boot config"
ok "boot config: new bootid, no persistence, gfl.media=dvd ($n files)"

# --- El Torito EFI boot image: a small FAT holding GRML's own EFI GRUB ----------------
efi_src="$(find "$STAGE" -maxdepth 3 -ipath "$STAGE/efi/boot/bootx64.efi" -type f | head -n1)"
[ -n "$efi_src" ] || die "no efi/boot/bootx64.efi on the image"
rm -f "$STAGE/boot/efi.img"
truncate -s 4M "$STAGE/boot/efi.img"
mkfs.vfat -n GFL_EFI "$STAGE/boot/efi.img" >/dev/null
mmd   -i "$STAGE/boot/efi.img" ::/EFI ::/EFI/BOOT
mcopy -i "$STAGE/boot/efi.img" "$efi_src" ::/EFI/BOOT/BOOTX64.EFI
ok "EFI boot image ($(basename "$efi_src"))"

# --- the disc ----------------------------------------------------------------
say "writing $OUT"
mkdir -p "$(dirname "$OUT")"
xorriso -as mkisofs -quiet \
  -iso-level 3 -full-iso9660-filenames -joliet -joliet-long -rational-rock \
  -volid "$VOLID" -appid "GopForge-Live" -publisher "github.com/KurdtNervanna/GopForgeLive" \
  -eltorito-platform efi -e boot/efi.img -no-emul-boot \
  -o "$OUT" "$STAGE" || die "xorriso failed"
size="$(stat -c %s "$OUT")"
ok "disc image: $OUT ($(( size / 1048576 )) MiB)"
[ "$size" -gt 4700000000 ] && echo "! larger than a single-layer DVD (4.7 GB)"
[ "$size" -gt 734003200 ] && echo "  (needs a DVD — too big for a 700 MB CD)"

if [ -n "$DMG" ]; then
  say "writing $DMG"
  rm -f "$DMG"
  dmg "$OUT" "$DMG" >/dev/null || die "dmg conversion failed"     # fanquake/libdmg-hfsplus: dmg <in> <out>
  [ "$(tail -c 512 "$DMG" | head -c 4)" = koly ] || die "dmg output isn't a UDIF image"
  ok "macOS disc image: $DMG ($(( $(stat -c %s "$DMG") / 1048576 )) MiB)"
fi
