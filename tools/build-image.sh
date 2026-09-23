#!/usr/bin/env bash
# build-image.sh — produce a ready-to-boot, auto-launching GopForge-Live USB.
#
# Pipeline (Linux):
#   1. (optional) write the GRML-FLASH base image to a USB   [--image + --device]
#   2. install the bundle onto the medium's FAT partition
#   3. wire an autostart hook so bin/gopwizard.sh runs on boot (no shell needed)
#
# Usage:
#   sudo ./tools/build-image.sh --device /dev/sdX --image <grml-flash.img>
#   sudo ./tools/build-image.sh --mount /media/usb           # already-written USB
#   ... [--no-autostart] [--no-write]
#
# The autostart wiring is BEST-EFFORT and UNTESTED — GRML boot layouts vary. The
# write + install steps are the reliable core; if autostart can't be wired the
# script prints the manual one-liner.
set -Eeuo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE=""; DEVICE=""; MNT=""; DO_WRITE=1; DO_AUTO=1
while [ $# -gt 0 ]; do
  case "$1" in
    --image)  IMAGE="$2"; shift 2;;
    --device) DEVICE="$2"; shift 2;;
    --mount)  MNT="$2"; shift 2;;
    --no-write) DO_WRITE=0; shift;;
    --no-autostart) DO_AUTO=0; shift;;
    -h|--help) grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "unknown arg: $1"; exit 2;;
  esac
done
[ "$(id -u)" = 0 ] || { echo "run as root (sudo)."; exit 2; }

say(){ printf '\033[36m» %s\033[0m\n' "$*"; }
ok(){ printf '\033[32m✓ %s\033[0m\n' "$*"; }
warn(){ printf '\033[33m! %s\033[0m\n' "$*"; }

# 1. write base image
if [ -n "$DEVICE" ] && [ -n "$IMAGE" ] && [ "$DO_WRITE" = 1 ]; then
  say "writing base image to $DEVICE"
  "$REPO/flash-usb/write-image-linux.sh" "$IMAGE" "$DEVICE" --no-install
fi

# 2. resolve the FAT data partition mountpoint
if [ -z "$MNT" ]; then
  [ -n "$DEVICE" ] || { echo "need --mount or --device"; exit 2; }
  say "locating FAT data partition on $DEVICE"
  sleep 2
  MNT="$(mktemp -d)"; mounted=0
  for p in $(lsblk -lnpo NAME,FSTYPE "$DEVICE" | awk '$2 ~ /vfat|fat|exfat/ {print $1}'); do
    if mount "$p" "$MNT" 2>/dev/null; then mounted=1; MOUNTED_HERE="$MNT"; break; fi
  done
  [ "$mounted" = 1 ] || { echo "could not mount a FAT partition on $DEVICE"; exit 3; }
fi
[ -d "$MNT" ] || { echo "mount dir missing: $MNT"; exit 3; }

# 3. install the bundle
say "installing bundle onto $MNT"
"$REPO/tools/install-to-usb.sh" "$MNT"
TARGET="$MNT/gopforge-live"

# 4. autostart wiring (best-effort)
if [ "$DO_AUTO" = 1 ]; then
  # 4a. A medium-root stub with a fixed name that GRML `startup=` can point to.
  #     It self-locates the bundle under whatever the live medium mount is.
  cat > "$MNT/gopforge-autostart" <<'STUB'
#!/usr/bin/env bash
# GopForge-Live boot stub — find the bundle on the live medium and auto-start.
set -u
for d in /run/live/medium /lib/live/mount/medium /run/live/persistence/* /cdrom /live/image; do
  if [ -x "$d/gopforge-live/bin/autostart.sh" ]; then exec bash "$d/gopforge-live/bin/autostart.sh"; fi
done
# fallback: search
p="$(find /run/live /lib/live/mount /cdrom -maxdepth 5 -name autostart.sh -path '*gopforge-live*' 2>/dev/null | head -n1)"
[ -n "$p" ] && exec bash "$p"
exit 0
STUB
  chmod +x "$MNT/gopforge-autostart" 2>/dev/null || true
  ok "installed boot stub: <medium>/gopforge-autostart"

  # 4b. Inject a GRML `startup=` bootoption into any boot config we can find.
  #     grml-autoconfig runs `startup=<path>` late in boot, as root.
  STARTVAL="/run/live/medium/gopforge-autostart"
  injected=0
  while IFS= read -r cfg; do
    grep -q 'startup=/run/live/medium/gopforge-autostart' "$cfg" && { injected=1; continue; }
    if grep -qE '(^|[[:space:]])(linux|append|kernel)[[:space:]].*boot=live' "$cfg"; then
      cp -a "$cfg" "$cfg.gopforge.bak"
      # append the bootoption to lines that boot the live system
      sed -i -E "/boot=live/ s#\$# startup=$STARTVAL#" "$cfg"
      injected=1
      ok "added startup= to $(basename "$cfg") (backup: $cfg.gopforge.bak)"
    fi
  done < <(find "$MNT" -maxdepth 4 -type f \( -name 'grml*.cfg' -o -name 'grub.cfg' -o -name '*.cfg' -o -name 'syslinux.cfg' -o -name 'isolinux.cfg' \) 2>/dev/null)

  if [ "$injected" = 0 ]; then
    warn "no editable boot config found on the data partition."
    warn "autostart could not be wired automatically. Options:"
    echo "   • add the bootoption manually to your GRML boot menu:"
    echo "       startup=$STARTVAL"
    echo "   • OR, on a persistence partition, append to the live user's ~/.zlogin:"
    echo "       bash <medium>/gopforge-live/bin/autostart.sh"
  fi
fi

sync
[ -n "${MOUNTED_HERE:-}" ] && { umount "$MOUNTED_HERE" 2>/dev/null || true; rmdir "$MOUNTED_HERE" 2>/dev/null || true; }
ok "done — boot the target Mac from this USB."
echo "  (autostart is best-effort/untested; if it doesn't launch, run:"
echo "   sudo bash <data-partition>/gopforge-live/bin/gopwizard.sh )"
