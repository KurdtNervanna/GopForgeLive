# shellcheck shell=bash
# ui.sh — terminal + whiptail helpers for GopForge-Live.
# Sourced by gopwizard.sh; never executed directly.
#
# IMPORTANT: everything the operator should SEE goes to the controlling terminal
# ($GFL_TTY, normally /dev/tty) — never to stdout. Many helpers return values on
# stdout via $(...), and under the auto-launch systemd service stderr goes to the
# journal, so drawing on stdout/stderr made menus invisible and polluted return
# values (a dump path captured with status lines glued to it).

# Controlling terminal, or stderr if there is none (e.g. a pipe in a test).
GFL_TTY=/dev/tty
( : >/dev/tty ) 2>/dev/null || GFL_TTY=/dev/stderr

# --- plain-terminal colored status markers (mirrors gopforge.sh) -------------
if [ -t 1 ] || [ "$GFL_TTY" = /dev/tty ]; then
  if [ "${GFL_NO_COLOR:-0}" != "1" ]; then
    C_RESET=$'\033[0m'; C_OK=$'\033[32m'; C_ERR=$'\033[31m'
    C_WARN=$'\033[33m'; C_INFO=$'\033[36m'; C_DIM=$'\033[2m'
  fi
fi
: "${C_RESET:=}" "${C_OK:=}" "${C_ERR:=}" "${C_WARN:=}" "${C_INFO:=}" "${C_DIM:=}"

# Single log file on the working tree so a headless/SSH session can tail it.
GFL_LOG="${GFL_LOG:-${GFL_WORKDIR:-/tmp}/gopforge-live.log}"

_log() { # level msg...
  local lvl="$1"; shift
  printf '%s [%s] %s\n' "$(date '+%H:%M:%S')" "$lvl" "$*" >>"$GFL_LOG" 2>/dev/null || true
  sync -f "$GFL_LOG" 2>/dev/null || true   # the USB may be pulled / power-cycled any time
}
_say() { printf '%s\n' "$*" >"$GFL_TTY" 2>/dev/null || printf '%s\n' "$*" >&2; }

ok()   { _say "${C_OK}✓${C_RESET} $*";   _log OK   "$*"; }
err()  { _say "${C_ERR}✗${C_RESET} $*";  _log ERR  "$*"; printf '✗ %s\n' "$*" >&2; }
warn() { _say "${C_WARN}!${C_RESET} $*"; _log WARN "$*"; }
info() { _say "${C_INFO}»${C_RESET} $*"; _log INFO "$*"; }
dim()  { _say "${C_DIM}$*${C_RESET}"; }

die()  { err "$*"; exit 1; }

# --- whiptail wrappers -------------------------------------------------------
# All fall back to plain prompts when whiptail is missing (or forced off with a
# "gopforge-plain" file on the USB) so the tool still works on any console.
HAVE_WHIPTAIL=0
command -v whiptail >/dev/null 2>&1 && HAVE_WHIPTAIL=1

_plain_read() { # prompt varname — prompt + read on the terminal
  printf '%s' "$1" >"$GFL_TTY"
  IFS= read -r "$2" <"$GFL_TTY" || printf -v "$2" '%s' ""
}

ui_msg() { # title body
  _log UI "msg: $1"
  if [ "$HAVE_WHIPTAIL" = 1 ]; then
    whiptail --title "$1" --msgbox "$2" 20 76 <"$GFL_TTY" >"$GFL_TTY"
  else
    printf '\n== %s ==\n%s\n' "$1" "$2" >"$GFL_TTY"; local _x; _plain_read "[enter] " _x
  fi
}

# Returns 0 for yes, 1 for no. Defaults to NO (safety) unless overridden.
ui_yesno() { # title body [defaultyes]
  local rc
  if [ "$HAVE_WHIPTAIL" = 1 ]; then
    local def="--defaultno"; [ "${3:-}" = "defaultyes" ] && def=""
    whiptail --title "$1" $def --yesno "$2" 20 76 <"$GFL_TTY" >"$GFL_TTY"; rc=$?
  else
    printf '\n== %s ==\n%s\n' "$1" "$2" >"$GFL_TTY"
    local p="[y/N] " ans; [ "${3:-}" = "defaultyes" ] && p="[Y/n] "
    _plain_read "$p" ans
    if [ "${3:-}" = "defaultyes" ]; then [ "$ans" != "n" ] && [ "$ans" != "N" ]; rc=$?
    else { [ "$ans" = "y" ] || [ "$ans" = "Y" ]; }; rc=$?; fi
  fi
  _log UI "yesno: $1 -> $([ $rc -eq 0 ] && echo yes || echo no)"
  return $rc
}

# Echoes the chosen tag on stdout; returns non-zero on cancel. The UI is drawn
# on the terminal; whiptail writes the choice to stderr, which we route to
# stdout for the caller's $(...).
ui_menu() { # title body tag1 item1 tag2 item2 ...
  local title="$1" body="$2" out rc; shift 2
  if [ "$HAVE_WHIPTAIL" = 1 ]; then
    out="$(whiptail --title "$title" --notags --menu "$body" 22 76 12 "$@" \
             2>&1 >"$GFL_TTY" <"$GFL_TTY")"; rc=$?
  else
    printf '\n== %s ==\n%s\n' "$title" "$body" >"$GFL_TTY"
    local i=1 tags=() sel
    while [ $# -gt 0 ]; do tags+=("$1"); printf '  %d) %s\n' "$i" "$2" >"$GFL_TTY"; shift 2; i=$((i+1)); done
    _plain_read "select #: " sel
    if [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le "${#tags[@]}" ]; then
      out="${tags[$((sel-1))]}"; rc=0
    else out=""; rc=1; fi
  fi
  _log UI "menu: $title -> ${out:-<cancel>}"
  [ $rc -eq 0 ] || return 1
  printf '%s\n' "$out"
}

# Show a scrollable text file / long output.
ui_textbox() { # title file
  _log UI "textbox: $1"
  if [ "$HAVE_WHIPTAIL" = 1 ]; then
    whiptail --title "$1" --scrolltext --textbox "$2" 24 78 <"$GFL_TTY" >"$GFL_TTY"
  else
    printf '\n== %s ==\n' "$1" >"$GFL_TTY"; cat "$2" >"$GFL_TTY"; local _x; _plain_read "[enter] " _x
  fi
}
