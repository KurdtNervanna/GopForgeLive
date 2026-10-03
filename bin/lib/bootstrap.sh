# shellcheck shell=bash
# bootstrap.sh — shared startup for the text wizard (gopwizard.sh) and the GUI
# backend API (gfl-api). The caller must set GFL_BIN (its own directory) first.

GFL_VERSION="0.3.1-beta"
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

# Session snapshot for the log, so every session — app or text wizard — leaves
# useful diagnostics on the USB even if nothing else happens.
gfl_log_session() { # frontend
  machine_profile
  {
    echo "================ GopForge-Live session $(date 2>/dev/null) — ${1:-?} ================"
    echo "version : $GFL_VERSION"
    echo "cmdline : $(cat /proc/cmdline 2>/dev/null)"
    echo "medium  : ${GFL_MEDIUM:-<none>}   workdir: $GFL_WORKDIR"
    echo
    detect_report
    echo
    echo "machine class : $GFL_MACHINE_CLASS  (bootrom=$GFL_ALLOW_BOOTROM gpu=$GFL_ALLOW_GPU)"
    echo "$GFL_MACHINE_NOTE"
    echo "amdvbflash : ${GFL_AMDVBFLASH:-<not found>}"
    echo "nvflash    : ${GFL_NVFLASH:-<not found>}"
    echo "flashrom   : $(command -v flashrom 2>/dev/null || echo '<not found>')"
    echo "injector   : $(linux_dxeinject 2>/dev/null || echo '<not available>')"
    echo "==========================================================================="
  } >>"$GFL_LOG" 2>&1
  sync 2>/dev/null || true
}

# Escape hatch: an empty file named "gopforge-plain" on the USB forces the
# plain-text menus in the text wizard.
if [ -n "${GFL_MEDIUM:-}" ] && [ -e "$GFL_MEDIUM/gopforge-plain" ]; then HAVE_WHIPTAIL=0; fi
