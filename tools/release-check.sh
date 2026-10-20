#!/usr/bin/env bash
# release-check.sh — audit release images before they're published.
#
#   sudo tools/release-check.sh --img gopforge-live-<ver>.img --version <ver>
#   sudo tools/release-check.sh --iso gopforge-live-<ver>.iso [--dmg <ver>.dmg] --version <ver>
#
# Fails (exit 1) if an image is missing a piece the app needs, carries the wrong
# version, or contains anything that must never be published: Apple firmware
# (templates, .fd files), Boot ROM / graphics backups, logs or hardware reports
# from a test machine, dosdude1's macOS DXEInject, git metadata or Python caches.
set -Eeuo pipefail

IMG=""; ISO=""; DMG=""; VERSION=""
while [ $# -gt 0 ]; do
  case "$1" in
    --img) IMG="$2"; shift 2;;
    --iso) ISO="$2"; shift 2;;
    --dmg) DMG="$2"; shift 2;;
    --version) VERSION="$2"; shift 2;;
    *) echo "unknown arg: $1"; exit 2;;
  esac
done
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 2; }
[ -n "$VERSION" ] && { [ -n "$IMG" ] || [ -n "$ISO" ]; } || { echo "usage: $0 --img X.img|--iso X.iso [--dmg X.dmg] --version V"; exit 2; }

FAILS=0
pass(){ printf '  \033[32m✓\033[0m %s\n' "$*"; }
bad(){  printf '  \033[31m✗ %s\033[0m\n' "$*"; FAILS=$((FAILS+1)); }
check(){ local what="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$what"; else bad "$what"; fi; }
none(){  # what  find-args… — passes when find prints nothing
  local what="$1" root="$2"; shift 2; local hits
  hits="$(find "$root" "$@" 2>/dev/null | head -5)"
  if [ -z "$hits" ]; then pass "$what"; else bad "$what:"; sed 's/^/      /' <<<"$hits"; fi
}

MNT=""; LOOP=""; MOD=""; TMP="$(mktemp -d)"
cleanup(){ set +e; [ -n "$MOD" ] && umount "$MOD" 2>/dev/null; [ -n "$MNT" ] && umount "$MNT" 2>/dev/null; [ -n "$LOOP" ] && losetup -d "$LOOP" 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT

if [ -n "$IMG" ]; then
  echo "USB image: $IMG"
  LOOP="$(losetup -fP --show -r "$IMG")"; sleep 1
  MNT="$TMP/medium"; mkdir -p "$MNT"
  mount -o ro "${LOOP}p1" "$MNT" 2>/dev/null || mount -o ro,offset=$((2048*512)) "$IMG" "$MNT"
else
  echo "DVD image: $ISO"
  MNT="$TMP/medium"; mkdir -p "$MNT"
  mount -o ro,loop "$ISO" "$MNT"
fi
M="$MNT"

# --- the boot medium ------------------------------------------------------------
LIVE="$(dirname "$(find "$M/live" -name 'zz-gopforge.squashfs' | head -1)")"
check "our module is on the medium" test -f "$LIVE/zz-gopforge.squashfs"
for l in "$LIVE"/*.module; do
  [ -f "$l" ] && check "module registered in $(basename "$l")" grep -qx 'zz-gopforge.squashfs' "$l"
done
check "every live-boot entry has iomem=relaxed (flashrom)" \
  bash -c "! grep -h 'boot=live' '$M'/boot/grub/*.cfg | grep -v iomem=relaxed | grep -q ."
none "no user data folder on the medium" "$M" -maxdepth 2 -ipath "$M/gopforge-live/*" -type f
# (flash/ is GRML-FLASH's own tool + ROM collection, shipped as-is in the base image.)
none "no Apple firmware, backups or logs on the medium" "$M" \( -path "$M/flash" -o -path "$M/live" \) -prune -o \
  \( -iname '*.fd' -o -iname 'templates*.zip' -o -iname '*template*.bin' -o -iname 'bootrom-*.rom' -o -iname '*-adapter*-*.rom' -o -iname 'nvidia-idx*.rom' -o -iname '*.log' \) -print
if [ -n "$ISO" ]; then
  check "disc has a UEFI El Torito boot entry" bash -c "xorriso -indev '$ISO' -report_el_torito plain 2>/dev/null | grep -q 'UEFI'"
  check "disc boot entries carry gfl.media=dvd" bash -c "! grep -h 'boot=live' '$M'/boot/grub/*.cfg | grep -v gfl.media=dvd | grep -q ."
  check "disc boot entries don't ask for persistence" bash -c "! grep -h 'boot=live' '$M'/boot/grub/*.cfg | grep -qw persistence"
  check "disc bootid matches its boot config" bash -c "grep -rqF \"bootid=\$(cat '$M/conf/bootid.txt')\" '$M/boot/grub'"
fi

# --- the app module -------------------------------------------------------------
MOD="$TMP/module"; mkdir -p "$MOD"
mount -o ro,loop "$LIVE/zz-gopforge.squashfs" "$MOD"
O="$MOD/opt/gopforge-live"
check "app version is $VERSION" grep -q "^GFL_VERSION=\"$VERSION\"" "$O/bin/lib/bootstrap.sh"
for f in bin/gopwizard.sh bin/gfl-api bin/autostart.sh bin/jq bin/lib/storage.sh gui/server.py gui/session.sh \
         catalog/imac-boot-screen-matrix.json THIRD-PARTY.md vendor/gopforge/gopforge.sh; do
  check "has $f" test -e "$O/$f"
done
check "ROM library present (100+ ROMs)" bash -c "[ \$(find '$O/roms' -iname '*.rom' | wc -l) -ge 100 ]"
check "EnableGop drivers cached for offline use" test -f "$O/vendor/gopforge/tools/EnableGop.ffs"
check "Linux injector + its licenses present" bash -c "[ -x '$O/vendor/dxeinject-linux/dxeinject.bin' ] && ls '$O/vendor/dxeinject-linux/licenses/'*.copyright"
rc=0; "$O/vendor/dxeinject-linux/dxeinject" >/dev/null 2>&1 || rc=$?
if [ "$rc" = 64 ]; then pass "Linux injector loads (usage exit 64)"; else bad "Linux injector didn't load (exit $rc)"; fi
check "autostart service enabled for grml-boot.target" test -L "$MOD/etc/systemd/system/grml-boot.target.wants/gopforge.service"
none "no macOS DXEInject (not redistributable)" "$O" -name 'DXEInject' -type f
none "no git metadata" "$O" -name '.git'
none "no Python caches (they embed build paths)" "$O" \( -name '__pycache__' -o -name '*.pyc' \)
none "no dev/mock tree" "$O" -maxdepth 1 -name dev
none "no logs, reports or backups" "$O" \( -name '*.log' -o -path '*/Backups/*' -o -path '*/reports/*' -o -path '*/submissions/*' \)
none "no Apple firmware in the module" "$O" \( -iname '*.fd' -o -iname 'templates*.zip' -o -iname 'bootrom-*.rom' \)
umount "$MOD"; MOD=""

if [ -n "$DMG" ]; then
  check "the .dmg is a UDIF image" bash -c "tail -c 512 '$DMG' | head -c 4 | grep -q koly"
  if command -v dmg2img >/dev/null 2>&1 && [ -n "$ISO" ]; then
    dmg2img -s -i "$DMG" -o "$TMP/rt.img" >/dev/null 2>&1 || true
    check "the .dmg decodes to exactly the .iso" cmp -s "$ISO" "$TMP/rt.img"
    rm -f "$TMP/rt.img"
  fi
fi

echo
if [ "$FAILS" -gt 0 ]; then echo "✗ $FAILS check(s) failed"; exit 1; fi
echo "✓ all checks passed"
