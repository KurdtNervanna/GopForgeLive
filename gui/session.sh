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
# Current mode, e.g. "1440 900". There is no window manager in this session, so
# Firefox can't ask one for fullscreen — we size its window to the screen instead.
read -r width height < <(xrandr 2>/dev/null | awk '/\*/ { split($1, a, "x"); sub(/[^0-9].*/, "", a[2]); print a[1], a[2]; exit }')
scale=1
[ "${width:-0}" -ge 2400 ] && scale=1.5                 # 27" iMac 2560x1440
[ "${width:-0}" -ge 3600 ] && scale=2
echo "screen ${width:-?}x${height:-?} → scale $scale"

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
prof="$RUN/firefox-profile"; rm -rf "$prof"; mkdir -p "$prof"
cp "$BUNDLE/gui/firefox/user.js" "$prof/user.js"
printf 'user_pref("layout.css.devPixelsPerPx", "%s");\n' "$scale" >>"$prof/user.js"

rm -f /run/gopforge-textmode
started=$(date +%s)
MOZ_ENABLE_WAYLAND=0 MOZ_CRASHREPORTER_DISABLE=1 \
  "$ff" --kiosk --no-remote --profile "$prof" ${width:+--width "$width"} ${height:+--height "$height"}       "http://127.0.0.1:$PORT/?t=$(cat "$token")" &
ffpid=$!
wait "$ffpid"; rc=$?
ran=$(( $(date +%s) - started ))
echo "firefox exited rc=$rc after ${ran}s"
kill "$srv" 2>/dev/null

if [ -e /run/gopforge-textmode ]; then rm -f /run/gopforge-textmode; finish 10; fi
[ "$ran" -lt 20 ] && finish 2      # died almost immediately → treat as a failure
finish 0
