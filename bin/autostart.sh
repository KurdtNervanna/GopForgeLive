#!/usr/bin/env bash
# autostart.sh — launch GopForge Live automatically at boot.
#
# Started on tty1 by gopforge.service (see tools/remaster-image.sh). Tries the
# graphical app first (X + Firefox kiosk, gui/session.sh); if that can't start,
# crashes, or the user picks "Switch to Text Mode", it falls back to the text
# wizard. Does nothing over SSH or on a non-interactive stream, so a remote
# operator keeps a normal shell.
#
# Escape hatches (empty files at the top of the USB):
#   gopforge-tui    skip the graphical app, go straight to the text wizard
#   gopforge-plain  text wizard with plain numbered menus instead of whiptail
set -u

BUNDLE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RUN=/run/gopforge-gui

# whiptail/newt needs a terminal type; a bare systemd service provides none.
export TERM="${TERM:-linux}" HOME="${HOME:-/root}"

# Never hijack an SSH session or a non-tty.
case "${SSH_CONNECTION:-}${SSH_TTY:-}" in ?*) exit 0 ;; esac
[ -t 0 ] && [ -t 1 ] || exit 0

# The USB's writable FAT partition (for the escape-hatch files).
medium=""
for m in /run/live/persistence/* /lib/live/mount/persistence/*; do
  mountpoint -q "$m" 2>/dev/null || continue
  { [ -d "$m/flash" ] || [ -d "$m/live" ]; } && { medium="$m"; break; }
done

gui_possible() {
  [ -z "${GFL_NO_GUI:-}" ] || return 1
  [ -n "$medium" ] && [ -e "$medium/gopforge-tui" ] && return 1
  command -v xinit >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1 &&
    { command -v firefox-esr >/dev/null 2>&1 || command -v firefox >/dev/null 2>&1; }
}

clear 2>/dev/null || true
cat <<BANNER

  GopForge Live
  $(gui_possible && echo "Starting the graphical app…" || echo "Starting the text wizard…")
  Press Ctrl-C in the next 3 seconds to stay at a shell instead.

BANNER
# Give the operator a chance to bail out to a plain shell.
if ! sleep 3; then echo "…staying at shell."; exit 0; fi

if gui_possible; then
  mkdir -p "$RUN"; rm -f "$RUN/result"
  # Run X on its own VT; when it exits the console returns here (tty1).
  xinit "$BUNDLE/gui/session.sh" -- :0 vt7 -nolisten tcp -quiet >>"$RUN/xinit.log" 2>&1
  rc="$(cat "$RUN/result" 2>/dev/null || echo 2)"
  chvt 1 2>/dev/null || true
  clear 2>/dev/null || true
  case "$rc" in
    10) echo "Switching to the text wizard…" ;;
    0)  echo "The graphical app closed — starting the text wizard." ;;
    *)  echo "The graphical app couldn't start on this Mac — using the text wizard instead."
        echo "(Details: $RUN/session.log and $RUN/xinit.log)"; sleep 4 ;;
  esac
fi

# root needed for flashrom/amdvbflash/nvflash.
if [ "$(id -u)" = 0 ]; then exec bash "$BUNDLE/bin/gopwizard.sh"
else exec sudo bash "$BUNDLE/bin/gopwizard.sh"; fi
