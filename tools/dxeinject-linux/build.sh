#!/usr/bin/env bash
# build.sh — build the Linux DXEInject (tools/dxeinject-linux/main.cpp on UEFITool
# 0.28.0's FfsEngine) into vendor/dxeinject-linux/, ready to ride on the USB.
#
# Builds inside a Debian bookworm chroot so the binary's glibc floor (2.36) is at
# or below GRML-FLASH's, and bundles Qt5Core + its non-glibc deps next to it.
#
# Needs: Linux, root, debootstrap, git.   Usage: sudo tools/dxeinject-linux/build.sh
set -Eeuo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC="$HERE/tools/dxeinject-linux"
OUT="$HERE/vendor/dxeinject-linux"
CHROOT="${CHROOT:-/var/tmp/gfl-bookworm}"
UEFITOOL_REPO="https://github.com/LongSoft/UEFITool.git"
UEFITOOL_TAG="0.28.0"
UEFITOOL_COMMIT="d9642c53e7b873fcce858ec2bea577f099b966d5"

die() { echo "✗ $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || die "run as root (debootstrap/chroot)"
for t in debootstrap git; do command -v "$t" >/dev/null || die "missing tool: $t"; done

if [ ! -x "$CHROOT/usr/lib/qt5/bin/qmake" ]; then
  echo "» creating bookworm build chroot at $CHROOT …"
  debootstrap --variant=minbase --include=qtbase5-dev,build-essential,ca-certificates \
    bookworm "$CHROOT" http://deb.debian.org/debian >/dev/null
fi

B="$CHROOT/build"
rm -rf "$B"; mkdir -p "$B"
echo "» fetching UEFITool $UEFITOOL_TAG …"
git clone -q --depth 1 --branch "$UEFITOOL_TAG" "$UEFITOOL_REPO" "$B/UEFITool"
[ "$(git -C "$B/UEFITool" rev-parse HEAD)" = "$UEFITOOL_COMMIT" ] || die "UEFITool $UEFITOOL_TAG is not the pinned commit"

mkdir -p "$B/UEFITool/DXEInjectLinux"
cp "$SRC/main.cpp" "$B/UEFITool/DXEInjectLinux/"
# Same source list as UEFIPatch (console FfsEngine), with our main.
sed -e 's/^TARGET .*/TARGET = dxeinject.bin/' \
    -e 's#uefipatch_main.cpp#main.cpp#' \
    -e '/ uefipatch\.cpp/d' \
    -e 's#HEADERS  += uefipatch.h#HEADERS  +=#' \
    "$B/UEFITool/UEFIPatch/uefipatch.pro" > "$B/UEFITool/DXEInjectLinux/DXEInjectLinux.pro"

echo "» compiling in the chroot …"
mount -t proc proc "$CHROOT/proc" 2>/dev/null || true
trap 'umount "$CHROOT/proc" 2>/dev/null || true' EXIT
chroot "$CHROOT" /bin/sh -c 'cd /build/UEFITool/DXEInjectLinux && /usr/lib/qt5/bin/qmake DXEInjectLinux.pro >/dev/null && make -j"$(nproc)" >/dev/null 2>&1 || make 2>&1 | tail -30'
BIN="$B/UEFITool/DXEInjectLinux/dxeinject.bin"
[ -x "$BIN" ] || die "build failed"

echo "» bundling …"
rm -rf "$OUT"; mkdir -p "$OUT/lib"
cp "$BIN" "$OUT/dxeinject.bin"
# every shared dep except the glibc family (the host's newer glibc is used)
chroot "$CHROOT" ldd /build/UEFITool/DXEInjectLinux/dxeinject.bin | awk '/=> \//{print $3}' |
while read -r lib; do
  case "$(basename "$lib")" in
    libc.so*|libm.so*|libdl.so*|libpthread.so*|librt.so*|ld-linux*) continue ;;
  esac
  cp -L "$CHROOT$lib" "$OUT/lib/"
done
strip --strip-unneeded "$OUT/dxeinject.bin" "$OUT"/lib/*.so* 2>/dev/null || true

cat > "$OUT/dxeinject" <<'EOF'
#!/bin/sh
# Linux DXEInject: runs the bundled binary against its bundled Qt5Core.
d="$(dirname "$(readlink -f "$0")")"
LD_LIBRARY_PATH="$d/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" exec "$d/dxeinject.bin" "$@"
EOF
chmod +x "$OUT/dxeinject" "$OUT/dxeinject.bin"
cp "$B/UEFITool/LICENSE.md" "$OUT/LICENSE-UEFITool.md"
cat > "$OUT/BUILDINFO" <<EOF
dxeinject (Linux) for GopForge-Live
source:   tools/dxeinject-linux/main.cpp
engine:   UEFITool $UEFITOOL_TAG ($UEFITOOL_COMMIT), BSD-2-Clause — see LICENSE-UEFITool.md
built:    $(date -u +%Y-%m-%dT%H:%M:%SZ) in Debian bookworm chroot
sha256:   $(sha256sum "$OUT/dxeinject.bin" | cut -d' ' -f1)  dxeinject.bin
EOF
du -sh "$OUT"
"$OUT/dxeinject" 2>&1 | head -1 || true
echo "✓ vendor/dxeinject-linux ready"
