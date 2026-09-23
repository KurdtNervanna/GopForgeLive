#!/usr/bin/env bash
# install-to-usb.sh — copy GopForge-Live onto an existing GRML-FLASH USB.
#
# This is the fast iteration path: instead of rebuilding a live image, drop the
# whole bundle onto the mounted GRML-FLASH persistence/data partition and run
# bin/gopwizard.sh from there inside the booted live environment.
#
# Usage: ./tools/install-to-usb.sh /path/to/mounted/usb
set -Eeuo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${1:-}"
[ -n "$DEST" ] || { echo "usage: $0 /path/to/mounted/usb"; exit 2; }
[ -d "$DEST" ] || { echo "not a directory: $DEST"; exit 2; }

TARGET="$DEST/gopforge-live"
echo "» installing GopForge-Live to $TARGET"
mkdir -p "$TARGET"

# Copy the runnable parts (skip git + local roms cache is copied if present).
for d in bin catalog docs vendor roms; do
  [ -e "$HERE/$d" ] || continue
  cp -a "$HERE/$d" "$TARGET/"
done
cp -a "$HERE/README.md" "$TARGET/" 2>/dev/null || true

# Ensure scripts are executable + LF (FAT keeps no exec bit, so also provide a
# launcher that calls bash explicitly).
chmod +x "$TARGET/bin/gopwizard.sh" 2>/dev/null || true
cat > "$TARGET/run.sh" <<'EOF'
#!/usr/bin/env bash
# Launcher for FAT media where the exec bit is lost.
cd "$(dirname "$0")"
exec sudo bash bin/gopwizard.sh "$@"
EOF
chmod +x "$TARGET/run.sh" 2>/dev/null || true

echo "✓ installed. Inside the booted GRML-FLASH environment run:"
echo "    cd <this-partition>/gopforge-live && sudo bash bin/gopwizard.sh"
