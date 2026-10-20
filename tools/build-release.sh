#!/usr/bin/env bash
# build-release.sh — build every release asset from a clean checkout:
#
#   dist/gopforge-live-<ver>.img.xz   USB stick image (balenaEtcher reads .xz directly)
#   dist/gopforge-live-<ver>.iso      DVD image — burn from Windows, Linux or macOS
#   dist/gopforge-live-<ver>.dmg      the same DVD as a macOS disk image
#   dist/SHA256SUMS.txt, dist/RELEASE-NOTES.md, dist/VERSION
#
#   sudo tools/build-release.sh [--out dist] [--work build] [--install-deps]
#
# This is what .github/workflows/release.yml runs; it behaves the same on any
# Debian/Ubuntu machine (or WSL) as root. Every input is pinned:
#   GRML-FLASH base image ............ release + sha256 below
#   UEFITool (Linux EnableGop injector) tools/dxeinject-linux/build.sh
#   libdmg-hfsplus (.dmg writer) ...... commit below
# GopForge and the IMAC-EFI-BOOT-SCREEN ROM library follow GOPFORGE_REF / IMAC_ROMS_REF
# (default: their main branches) — pin them in the environment for a rebuild.
set -Eeuo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$REPO/dist"; WORK="$REPO/build"; DEPS=0; DEPS_ONLY=0

GRML_FLASH_URL="${GRML_FLASH_URL:-https://github.com/Ausdauersportler/GRML-FLASH/releases/download/v2.0.0/NOVEMBER_BLUES.dmg}"
GRML_FLASH_SHA256="${GRML_FLASH_SHA256:-1138ea67cea2bf9c3b2ec00e23e653745533f06ddd33be3c7b790a44ddfce93c}"
LIBDMG_REPO="https://github.com/fanquake/libdmg-hfsplus.git"
LIBDMG_COMMIT="1cc791e4173da9cb0b0cc16c5a1aaa25d5eb5efa"
APT_PKGS="squashfs-tools rsync gdisk fatresize dmg2img xorriso mtools dosfstools debootstrap git curl
          ca-certificates jq python3 perl xz-utils cmake build-essential zlib1g-dev util-linux"

while [ $# -gt 0 ]; do
  case "$1" in
    --out)  OUT="$(realpath -m "$2")"; shift 2;;
    --work) WORK="$(realpath -m "$2")"; shift 2;;
    --install-deps) DEPS=1; shift;;
    --install-deps-only) DEPS=1; DEPS_ONLY=1; shift;;
    -h|--help) grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "unknown arg: $1"; exit 2;;
  esac
done

die(){ echo "✗ $*" >&2; exit 1; }
step(){ printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok(){  printf '\033[32m✓ %s\033[0m\n' "$*"; }

[ "$(id -u)" = 0 ] || die "run as root (sudo): images are loop-mounted and the injector builds in a chroot"
# The checkout belongs to the invoking user (or the CI runner), not root; let git work
# on it and its vendored clones for this run only, without touching any git config.
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.directory GIT_CONFIG_VALUE_0='*'

if [ "$DEPS" = 1 ]; then
  step "installing build tools"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  # shellcheck disable=SC2086
  apt-get install -y -qq --no-install-recommends $APT_PKGS >/dev/null
  ok "build tools installed"
  [ "$DEPS_ONLY" = 1 ] && exit 0
fi
for t in mksquashfs rsync sgdisk fatresize dmg2img xorriso mmd mkfs.vfat debootstrap git curl jq python3 xz cmake losetup; do
  command -v "$t" >/dev/null 2>&1 || die "missing tool: $t (run with --install-deps)"
done

VERSION="$(sed -nE 's/^GFL_VERSION="([^"]+)".*/\1/p' "$REPO/bin/lib/bootstrap.sh")"
[ -n "$VERSION" ] || die "couldn't read GFL_VERSION from bin/lib/bootstrap.sh"
NAME="gopforge-live-$VERSION"
mkdir -p "$OUT" "$WORK"
rm -f "$OUT/$NAME".* "$OUT/SHA256SUMS.txt" "$OUT/RELEASE-NOTES.md"
echo "$VERSION" >"$OUT/VERSION"
step "GopForge-Live $VERSION → $OUT"

step "fetching GopForge + EnableGop tooling"
(cd "$REPO" && bash tools/fetch-vendor.sh)
step "fetching the IMAC-EFI-BOOT-SCREEN ROM library"
(cd "$REPO" && bash tools/fetch-roms.sh)
step "building the Linux EnableGop injector"
CHROOT="${CHROOT:-$WORK/bookworm}" bash "$REPO/tools/dxeinject-linux/build.sh"

step "GRML-FLASH base image"
base_dmg="$WORK/$(basename "$GRML_FLASH_URL")"
if [ ! -f "$base_dmg" ] || [ "$(sha256sum "$base_dmg" | cut -d' ' -f1)" != "$GRML_FLASH_SHA256" ]; then
  curl -fL --retry 3 -o "$base_dmg" "$GRML_FLASH_URL"
fi
[ "$(sha256sum "$base_dmg" | cut -d' ' -f1)" = "$GRML_FLASH_SHA256" ] || die "base image checksum mismatch"
ok "$(basename "$base_dmg") (sha256 verified)"
base_img="$WORK/base.img"
[ -s "$base_img" ] || dmg2img -s -i "$base_dmg" -o "$base_img" >/dev/null
ok "raw base image ready"

step "remastering the USB image"
bash "$REPO/tools/remaster-image.sh" --img "$base_img" --out "$WORK/$NAME.img"

step "release audit (USB image)"
bash "$REPO/tools/release-check.sh" --img "$WORK/$NAME.img" --version "$VERSION"

step "libdmg-hfsplus (for the .dmg)"
if [ ! -x "$WORK/libdmg/build/dmg/dmg" ]; then
  rm -rf "$WORK/libdmg"
  git clone -q "$LIBDMG_REPO" "$WORK/libdmg"
  git -C "$WORK/libdmg" checkout -q "$LIBDMG_COMMIT"
  cmake -S "$WORK/libdmg" -B "$WORK/libdmg/build" -DCMAKE_BUILD_TYPE=Release >/dev/null
  make -C "$WORK/libdmg/build/dmg" -j"$(nproc)" >/dev/null
fi
export PATH="$WORK/libdmg/build/dmg:$PATH"
ok "dmg tool ready"

step "DVD images"
bash "$REPO/tools/make-iso.sh" --img "$WORK/$NAME.img" --out "$OUT/$NAME.iso" --dmg "$OUT/$NAME.dmg"
step "release audit (DVD image)"
bash "$REPO/tools/release-check.sh" --iso "$OUT/$NAME.iso" --dmg "$OUT/$NAME.dmg" --version "$VERSION"

step "compressing the USB image"
img_sha="$(sha256sum "$WORK/$NAME.img" | cut -d' ' -f1)"
xz -T0 -6 -c "$WORK/$NAME.img" >"$OUT/$NAME.img.xz"
ok "$NAME.img.xz ($(( $(stat -c %s "$OUT/$NAME.img.xz") / 1048576 )) MiB)"

step "checksums + notes"
(cd "$OUT" && sha256sum "$NAME.img.xz" "$NAME.iso" "$NAME.dmg" >SHA256SUMS.txt
 echo "$img_sha  $NAME.img (uncompressed, after xz -d)" >>SHA256SUMS.txt)
mib(){ echo $(( $(stat -c %s "$OUT/$1") / 1048576 )); }
cat >"$OUT/RELEASE-NOTES.md" <<EOF
## Which file do I need?

| File | Use it to | Size |
|---|---|---|
| \`$NAME.img.xz\` | **Make a USB stick** (2 GB or more) with [balenaEtcher](https://etcher.balena.io/) — it reads the \`.xz\` directly. Recommended. | $(mib "$NAME.img.xz") MiB |
| \`$NAME.iso\` | **Burn a DVD** from Windows (right-click › Burn disc image), Linux (Brasero, K3b, \`growisofs\`) or macOS. | $(mib "$NAME.iso") MiB |
| \`$NAME.dmg\` | **Burn a DVD on a Mac**: the same disc as a macOS disk image (Finder › right-click › Burn, or \`hdiutil burn\`). | $(mib "$NAME.dmg") MiB |

The disc is about 1 GB, so it needs a **DVD±R** — it doesn't fit on a 700 MB CD.
Boot either one holding **⌥ Option** and pick **EFI Boot**.

**Booted from a DVD?** A disc can't be written to, so backups and the log stay in
memory until you choose **Save to USB…** (sidebar, or the text wizard's menu) and pick
a FAT32 or exFAT USB drive. Nothing is flashed until your backups are saved there.

Built $([ -n "${GITHUB_ACTIONS:-}" ] && echo "by GitHub Actions ")from \`$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo unknown)\` on GRML-FLASH $(basename "$(dirname "$GRML_FLASH_URL")").

### SHA-256
\`\`\`
$(cat "$OUT/SHA256SUMS.txt")
\`\`\`
EOF
ls -la "$OUT"
ok "release assets ready in $OUT"
