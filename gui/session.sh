#!/usr/bin/env bash
# session.sh — the X session for the GopForge Live kiosk (started by autostart.sh
# via xinit). Starts the local backend, then Firefox in kiosk mode pointed at it.
#
# Exit codes (read by autostart.sh):
#   0   the browser was closed normally
#   10  the user chose "Switch to Text Mode"
#   2   the GUI failed to come up (backend or browser died early) → text wizard
set -u
BUNDLE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${GFL_GUI_PORT:-8765}"
RUN=/run/gopforge-gui
mkdir -p "$RUN"
exec >>"$RUN/session.log" 2>&1
echo "== GopForge Live GUI session $(date)"
rm -f "$RUN/result"
finish() { echo "$1" >"$RUN/result"; exit "$1"; }   # xinit doesn't reliably relay our exit code

# --- display ---------------------------------------------------------------
xset s off s noblank -dpms 2>/dev/null || true          # never blank mid-flash
xsetroot -solid '#0b0d14' -cursor_name left_ptr 2>/dev/null || true
# Screen size: the X screen's "current W x H" (all outputs together), else the
# first active mode.
read -r width height < <(xrandr 2>/dev/null | awk '/ current [0-9]+ x [0-9]+/ {
  for (i = 1; i <= NF; i++) if ($i == "current") { h = $(i + 3); sub(/[^0-9].*/, "", h); print $(i + 1), h; exit } }')
[ -n "${width:-}" ] || read -r width height < <(xrandr 2>/dev/null | awk '/\*/ { split($1, a, "x"); sub(/[^0-9].*/, "", a[2]); print a[1], a[2]; exit }')
xrandr 2>/dev/null | sed -n '1,12p'
scale=1
[ "${width:-0}" -ge 2400 ] && scale=1.5                 # 27" iMac 2560x1440
[ "${width:-0}" -ge 3600 ] && scale=2
# Firefox reads --width/--height in CSS pixels, i.e. AFTER layout.css.devPixelsPerPx,
# so pass the screen size divided by the scale — else at 1.5x the window is 1.5x the
# screen and everything past the right/bottom edge is unreachable (seen on iMac12,2).
win_w="" win_h=""
if [ -n "${width:-}" ] && [ -n "${height:-}" ]; then
  win_w=$(awk -v v="$width"  -v s="$scale" 'BEGIN { printf "%d", v / s }')
  win_h=$(awk -v v="$height" -v s="$scale" 'BEGIN { printf "%d", v / s }')
fi
echo "screen ${width:-?}x${height:-?} → scale $scale, window ${win_w:-?}x${win_h:-?} CSS px"

# Manual override from the boot line, e.g. gfl.window=1600x900 (CSS px).
ovr="$(sed -n 's/.*gfl\.window=\([0-9]*x[0-9]*\).*/\1/p' /proc/cmdline 2>/dev/null)"
if [ -n "$ovr" ]; then win_w="${ovr%x*}"; win_h="${ovr#*x}"; echo "window size from the boot line: $ovr"; fi

# No window manager: the kiosk window is sized to the screen by hand. If it still
# comes up the wrong size (a Mac Pro once got 1024x576 on a 1920x1080 screen), the app
# reports its real viewport and the backend asks for ONE relaunch at the size Firefox
# itself measured — see the relaunch loop below.
export GFL_DISPLAY_INFO="screen ${width:-?}x${height:-?}, scale $scale, window ${win_w:-?}x${win_h:-?} CSS px"
export GFL_RELAUNCH_FILE="$RUN/relaunch"

# --- backend ---------------------------------------------------------------
token="$RUN/token"; rm -f "$token"
python3 "$BUNDLE/gui/server.py" --port "$PORT" --token-file "$token" &
srv=$!
up=0
for _ in $(seq 1 80); do
  if [ -s "$token" ] && (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null; then up=1; break; fi
  kill -0 "$srv" 2>/dev/null || break
  sleep 0.25
done
[ "$up" = 1 ] || { echo "backend failed to start"; kill "$srv" 2>/dev/null; finish 2; }

# --- browser ---------------------------------------------------------------
ff="$(command -v firefox-esr || command -v firefox || true)"
[ -n "$ff" ] || { echo "firefox not found"; kill "$srv"; finish 2; }
prof="$RUN/firefox-profile"
# A fresh profile per launch: a reused one remembers the old window size (xulstore)
# and can bring the killed window back as a second one.
new_profile() {
  rm -rf "$prof"; mkdir -p "$prof"
  cp "$BUNDLE/gui/firefox/user.js" "$prof/user.js"
  printf 'user_pref("layout.css.devPixelsPerPx", "%s");\n' "$scale" >>"$prof/user.js"
}

rm -f /run/gopforge-textmode
started=$(date +%s)
attempt=0
while :; do
  rm -f "$RUN/relaunch"; new_profile
  MOZ_ENABLE_WAYLAND=0 MOZ_CRASHREPORTER_DISABLE=1 \
    "$ff" --kiosk --no-remote --profile "$prof" ${win_w:+--width "$win_w"} ${win_h:+--height "$win_h"} \
    "http://127.0.0.1:$PORT/?t=$(cat "$token")" &
  ffpid=$!
  wait "$ffpid"; rc=$?
  # the backend asks for one relaunch when the window didn't match the screen
  if [ -s "$RUN/relaunch" ] && [ "$attempt" -lt 1 ]; then
    read -r win_w win_h <"$RUN/relaunch"; attempt=$((attempt + 1))
    echo "relaunching firefox at ${win_w}x${win_h} CSS px (window didn't match the screen)"
    pkill -KILL -f -- "--profile $prof" 2>/dev/null; sleep 0.5   # no stragglers from the old one
    continue
  fi
  break
done
ran=$(( $(date +%s) - started ))
echo "firefox exited rc=$rc after ${ran}s"
kill "$srv" 2>/dev/null

if [ -e /run/gopforge-textmode ]; then rm -f /run/gopforge-textmode; finish 10; fi
[ "$ran" -lt 20 ] && finish 2      # died almost immediately → treat as a failure
finish 0
