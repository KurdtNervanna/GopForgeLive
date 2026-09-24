# shellcheck shell=bash
# bootstrap.sh — shared startup for the text wizard (gopwizard.sh) and the GUI
# backend API (gfl-api). The caller must set GFL_BIN (its own directory) first.

GFL_VERSION="0.2.0-untested"
GFL_ROOT="$(cd -- "$GFL_BIN/.." && pwd)"
GFL_LIB="$GFL_BIN/lib"

# ROM library (IMAC-EFI-BOOT-SCREEN set fetched by tools/fetch-roms.sh).
GFL_ROMS="${GFL_ROMS:-$GFL_ROOT/roms}"

# Prefer a bundled static jq (the remastered image ships one) so matrix matching
# works even when the live OS has no jq of its own.
[ -x "$GFL_BIN/jq" ] && case ":$PATH:" in *":$GFL_BIN:"*) : ;; *) PATH="$GFL_BIN:$PATH";; esac

# shellcheck source=ui.sh
. "$GFL_LIB/ui.sh"
# shellcheck source=safety.sh
. "$GFL_LIB/safety.sh"
# The USB's rw FAT mount must be found in THIS shell (not inside $(...)), and the
# workdir must exist before the other libraries start logging into it.
GFL_MEDIUM="${GFL_MEDIUM:-$(gfl_find_usb || true)}"
GFL_WORKDIR="${GFL_WORKDIR:-$(gfl_resolve_workdir)}"
mkdir -p "$GFL_WORKDIR" 2>/dev/null || true
GFL_LOG="$GFL_WORKDIR/gopforge-live.log"
. "$GFL_LIB/detect.sh"
. "$GFL_LIB/library.sh"
. "$GFL_LIB/vbios.sh"
. "$GFL_LIB/bootrom.sh"

# Escape hatch: an empty file named "gopforge-plain" on the USB forces the
# plain-text menus in the text wizard.
if [ -n "${GFL_MEDIUM:-}" ] && [ -e "$GFL_MEDIUM/gopforge-plain" ]; then HAVE_WHIPTAIL=0; fi
