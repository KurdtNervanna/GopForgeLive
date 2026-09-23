#!/usr/bin/env bash
# remaster-image.sh — bake GopForge-Live into a GRML-FLASH image, producing a
# single all-in-one bootable file that auto-launches the wizard on boot.
#
#   sudo ./tools/remaster-image.sh --img <grml-flash.img> [--out <out.img>]
#                                  [--grow-mb N] [--comp gzip|zstd|xz]
#   # advanced / testing (no root): build just the module into a mounted live/ dir
#   ./tools/remaster-image.sh --build-module-only <path/to/live>
#
# HOW IT WORKS (non-destructive to the base squashfs):
#   GRML uses live-boot, which stacks EVERY squashfs found in the medium's live/
#   directory as an overlay. So instead of resquashing the multi-GB base, we build
#   ONE small additive module (zz-gopforge.squashfs) that adds:
#       /opt/gopforge-live/...            the wizard + ROM library + gopforge
#       /opt/gopforge-live/bin/jq         a static jq (matrix matching)
#       a systemd service + getty override that launches the wizard on tty1
#   and drop it into live/. The base image's partition table and Mac/PC boot code
#   are left untouched, which is what keeps it booting on a cMP/iMac.
#
# Prereqrequisites (Linux, root): losetup, mksquashfs (squashfs-tools), rsync,
# blkid, and a prepared checkout (run tools/fetch-vendor.sh + tools/fetch-roms.sh
# first). UNTESTED on hardware; live-boot module inclusion + the tty1 autostart
# may need per-version tuning — see docs/REMASTER.md.
set -Eeuo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
IMG=""; OUT=""; GROW_MB=0; COMP="gzip"; MODULE_ONLY=0; LIVEDIR_ARG=""
JQ_URL="${JQ_URL:-https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64}"
while [ $# -gt 0 ]; do
  case "$1" in
    --img)   IMG="$2"; shift 2;;
    --out)   OUT="$2"; shift 2;;
    --grow-mb) GROW_MB="$2"; shift 2;;
    --comp)  COMP="$2"; shift 2;;
    --build-module-only) MODULE_ONLY=1; LIVEDIR_ARG="$2"; shift 2;;
    -h|--help) grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "unknown arg: $1"; exit 2;;
  esac
done

die(){ echo "✗ $*" >&2; exit 1; }
say(){ printf '\033[36m» %s\033[0m\n' "$*"; }
ok(){  printf '\033[32m✓ %s\033[0m\n' "$*"; }

# Assemble the additive module tree and squash it into $LIVEDIR. Uses globals
# REPO / LIVEDIR / COMP / JQ_URL. Root-independent — safe to test standalone via
# --build-module-only against a plain directory.
gfl_build_module() {
  MODROOT="$(mktemp -d)"
  say "assembling additive module"
  install -d "$MODROOT/opt/gopforge-live"
  for d in bin catalog docs roms; do rsync -a "$REPO/$d" "$MODROOT/opt/gopforge-live/"; done
  install -d "$MODROOT/opt/gopforge-live/vendor"
  rsync -a "$REPO/vendor/gopforge" "$MODROOT/opt/gopforge-live/vendor/"
  rsync -a "$REPO/README.md" "$MODROOT/opt/gopforge-live/" 2>/dev/null || true

  # static jq for reliable matrix matching
  if command -v curl >/dev/null 2>&1; then
    say "fetching static jq for the image"
    curl -fsSL -o "$MODROOT/opt/gopforge-live/bin/jq" "$JQ_URL" && chmod +x "$MODROOT/opt/gopforge-live/bin/jq" \
      || echo "! jq fetch failed — image will fall back to name-based matching"
  fi
  chmod +x "$MODROOT/opt/gopforge-live/bin/"*.sh 2>/dev/null || true

  # autostart: a systemd service that runs the wizard on tty1, plus a getty
  # override so it owns the console.
  install -d "$MODROOT/etc/systemd/system" \
            "$MODROOT/etc/systemd/system/multi-user.target.wants" \
            "$MODROOT/etc/systemd/system/getty@tty1.service.d"
  cat > "$MODROOT/etc/systemd/system/gopforge.service" <<'UNIT'
[Unit]
Description=GopForge-Live wizard (auto-launch on tty1)
After=multi-user.target
Conflicts=getty@tty1.service

[Service]
Type=idle
ExecStart=/opt/gopforge-live/bin/autostart.sh
StandardInput=tty
StandardOutput=tty
StandardError=journal
TTYPath=/dev/tty1
TTYReset=yes
TTYVHangup=yes
Restart=no

[Install]
WantedBy=multi-user.target
UNIT
  ln -sf ../gopforge.service "$MODROOT/etc/systemd/system/multi-user.target.wants/gopforge.service"
  cat > "$MODROOT/etc/systemd/system/getty@tty1.service.d/override.conf" <<'OVR'
# Disabled: GopForge-Live owns tty1 (see gopforge.service).
[Unit]
ConditionPathExists=/opt/gopforge-live/DISABLED-BY-DEFAULT-NEVER
OVR

  local MOD="$LIVEDIR/zz-gopforge.squashfs"
  say "building $MOD (comp=$COMP)"
  rm -f "$MOD"
  mksquashfs "$MODROOT" "$MOD" -noappend -comp "$COMP" -no-progress >/dev/null \
    || die "mksquashfs failed (disk full? try --grow-mb)"
  ok "module: $(du -h "$MOD" | cut -f1)"

  # If live-boot uses an explicit module list (filesystem.module or any *.module),
  # append ours so it is included. The glob covers filesystem.module too.
  local lst
  for lst in "$LIVEDIR"/*.module; do
    [ -f "$lst" ] || continue
    grep -q 'zz-gopforge.squashfs' "$lst" || echo "zz-gopforge.squashfs" >> "$lst"
    ok "registered module in $(basename "$lst")"
  done
  rm -rf "$MODROOT"; MODROOT=""
}

# Common preflight (both modes need these).
for t in mksquashfs rsync; do command -v "$t" >/dev/null 2>&1 || die "missing tool: $t"; done
[ -d "$REPO/vendor/gopforge" ] || die "vendor/gopforge missing — run tools/fetch-vendor.sh"
[ -n "$(find "$REPO/roms" -name '*.rom' 2>/dev/null | head -n1)" ] || die "roms/ empty — run tools/fetch-roms.sh"

# --- test/advanced mode: build the module against a plain live dir, no root ---
if [ "$MODULE_ONLY" = 1 ]; then
  [ -d "$LIVEDIR_ARG" ] || die "--build-module-only needs an existing live/ directory"
  LIVEDIR="$LIVEDIR_ARG"
  gfl_build_module
  ok "module built into $LIVEDIR"
  if command -v unsquashfs >/dev/null 2>&1; then
    say "module contents (top of tree):"
    unsquashfs -l "$LIVEDIR/zz-gopforge.squashfs" 2>/dev/null | grep -E '/(opt/gopforge-live|etc/systemd)($|/[^/]*$)' | head -20
  fi
  exit 0
fi

# --- full image remaster (needs root) ---
[ "$(id -u)" = 0 ] || die "run as root (sudo)."
[ -n "$IMG" ] && [ -f "$IMG" ] || die "usage: sudo $0 --img <grml-flash.img|.dmg> [--out out.img]"
for t in losetup blkid mount umount; do command -v "$t" >/dev/null 2>&1 || die "missing tool: $t"; done

# GRML-FLASH ships a compressed .dmg; losetup needs a raw .img. Convert if needed.
case "$IMG" in
  *.dmg)
    command -v dmg2img >/dev/null 2>&1 \
      || die "input is a compressed .dmg — install a converter (sudo apt-get install -y dmg2img) or pass a raw .img"
    raw="${IMG%.dmg}.img"
    if [ ! -s "$raw" ]; then say "converting .dmg → raw .img (dmg2img)"; dmg2img -i "$IMG" -o "$raw" || die "dmg2img failed"; fi
    IMG="$raw"; ok "using raw image $IMG" ;;
esac

OUT="${OUT:-${IMG%.img}-gopforge.img}"
say "copying base image → $OUT"
cp --reflink=auto -f "$IMG" "$OUT"

# Optionally grow the file (does NOT resize partitions; only useful if the last
# FAT partition already has slack — most GRML-FLASH images do). For safety we
# just enlarge the container so a mildly-larger module fits when there's slack.
if [ "$GROW_MB" -gt 0 ]; then
  say "growing image by ${GROW_MB} MiB"
  truncate -s "+$((GROW_MB))M" "$OUT"
fi

cleanup() {
  set +e
  [ -n "${LIVE_MNT:-}" ] && { umount "$LIVE_MNT" 2>/dev/null; rmdir "$LIVE_MNT" 2>/dev/null; }
  [ -n "${LOOP:-}" ] && losetup -d "$LOOP" 2>/dev/null
  # detach any other loop devices backing OUT (e.g. from the offset-mount fallback)
  [ -n "${OUT:-}" ] && losetup -j "$OUT" 2>/dev/null | cut -d: -f1 | xargs -r -n1 losetup -d 2>/dev/null
  [ -n "${MODROOT:-}" ] && rm -rf "$MODROOT" 2>/dev/null
}
trap cleanup EXIT

say "attaching loop device"
LOOP="$(losetup -fP --show "$OUT")" || die "losetup failed"
ok "loop: $LOOP"
sleep 1

# Locate the FAT partition that holds the base squashfs and set LIVEDIR to the
# directory that CONTAINS it (GRML nests it, e.g. live/grml64-full/*.squashfs —
# not directly under live/). Try partition device nodes first, then fall back to
# an offset mount (WSL sometimes does not create loopNpN nodes).
LIVE_MNT="$(mktemp -d)"; LIVEDIR=""; PART=""; SQ=""
_scan_mounted() { SQ="$(find "$LIVE_MNT" -maxdepth 4 -type f -name '*.squashfs' 2>/dev/null | head -n1)"; [ -n "$SQ" ]; }

for p in "${LOOP}"p*; do
  [ -b "$p" ] || continue
  if mount -o rw "$p" "$LIVE_MNT" 2>/dev/null || mount "$p" "$LIVE_MNT" 2>/dev/null; then
    if _scan_mounted; then LIVEDIR="$(dirname "$SQ")"; PART="$p"; break; fi
    umount "$LIVE_MNT" 2>/dev/null
  fi
done

if [ -z "$LIVEDIR" ]; then
  # offset-mount fallback: first partition start from the GPT
  pstart="$(sgdisk -p "$OUT" 2>/dev/null | awk '/^ *[0-9]+ +[0-9]+/{print $2; exit}')"
  poff=$(( ${pstart:-2048} * 512 ))
  if mount -o rw,offset="$poff" "$OUT" "$LIVE_MNT" 2>/dev/null || mount -o offset="$poff" "$OUT" "$LIVE_MNT" 2>/dev/null; then
    if _scan_mounted; then LIVEDIR="$(dirname "$SQ")"; PART="offset $poff"; fi
  fi
fi

[ -n "$LIVEDIR" ] || die "could not find a *.squashfs on any partition of the image"
ok "live dir: ${LIVEDIR#$LIVE_MNT}  ($PART, base $(basename "$SQ"))"

# --- build + install the additive module ------------------------------------
gfl_build_module

sync
say "detaching"
umount "$LIVE_MNT"; rmdir "$LIVE_MNT"; LIVE_MNT=""
losetup -d "$LOOP"; LOOP=""
rm -rf "$MODROOT"; MODROOT=""
trap - EXIT

ok "remastered image ready: $OUT"
cat <<EOF

Write it to a USB with any of the flash-usb writers (or Etcher/Rufus), e.g.:
  sudo ./flash-usb/write-image-linux.sh "$OUT" /dev/sdX --no-install

On boot the wizard should come up on tty1 automatically. If it doesn't (live-boot
module inclusion / tty ownership varies by GRML build), fall back to a shell:
  sudo bash /run/live/medium/live/../opt/gopforge-live/bin/gopwizard.sh
See docs/REMASTER.md for tuning notes.
EOF
