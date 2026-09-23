# shellcheck shell=bash
# ui.sh — terminal + whiptail helpers for GopForge-Live.
# Sourced by gopwizard.sh; never executed directly.

# --- plain-terminal colored status markers (mirrors gopforge.sh) -------------
if [ -t 1 ] && [ "${GFL_NO_COLOR:-0}" != "1" ]; then
  C_RESET=$'\033[0m'; C_OK=$'\033[32m'; C_ERR=$'\033[31m'
  C_WARN=$'\033[33m'; C_INFO=$'\033[36m'; C_DIM=$'\033[2m'
else
  C_RESET=""; C_OK=""; C_ERR=""; C_WARN=""; C_INFO=""; C_DIM=""
fi

# Single log file on the working tree so a headless/SSH session can tail it.
GFL_LOG="${GFL_LOG:-${GFL_WORKDIR:-/tmp}/gopforge-live.log}"

_log() { # level msg...
  local lvl="$1"; shift
  printf '%s [%s] %s\n' "$(date '+%H:%M:%S')" "$lvl" "$*" >>"$GFL_LOG" 2>/dev/null || true
}

ok()   { printf '%s✓%s %s\n' "$C_OK"   "$C_RESET" "$*"; _log OK   "$*"; }
err()  { printf '%s✗%s %s\n' "$C_ERR"  "$C_RESET" "$*" >&2; _log ERR  "$*"; }
warn() { printf '%s!%s %s\n' "$C_WARN" "$C_RESET" "$*"; _log WARN "$*"; }
info() { printf '%s»%s %s\n' "$C_INFO" "$C_RESET" "$*"; _log INFO "$*"; }
dim()  { printf '%s%s%s\n'   "$C_DIM"  "$*" "$C_RESET"; }

die()  { err "$*"; exit 1; }

# --- whiptail wrappers -------------------------------------------------------
# All fall back to plain prompts when whiptail is missing so the tool still
# works over a bare serial/SSH console.
HAVE_WHIPTAIL=0
command -v whiptail >/dev/null 2>&1 && HAVE_WHIPTAIL=1

ui_msg() { # title body
  if [ "$HAVE_WHIPTAIL" = 1 ]; then
    whiptail --title "$1" --msgbox "$2" 20 76
  else
    printf '\n== %s ==\n%s\n' "$1" "$2"; read -r -p "[enter] " _
  fi
}

# Returns 0 for yes, 1 for no. Defaults to NO (safety) unless overridden.
ui_yesno() { # title body [defaultyes]
  if [ "$HAVE_WHIPTAIL" = 1 ]; then
    local def="--defaultno"; [ "${3:-}" = "defaultyes" ] && def=""
    whiptail --title "$1" $def --yesno "$2" 20 76
  else
    printf '\n== %s ==\n%s\n' "$1" "$2"
    local p="[y/N] "; [ "${3:-}" = "defaultyes" ] && p="[Y/n] "
    local ans; read -r -p "$p" ans
    if [ "${3:-}" = "defaultyes" ]; then [ "$ans" != "n" ] && [ "$ans" != "N" ]
    else [ "$ans" = "y" ] || [ "$ans" = "Y" ]; fi
  fi
}

# Echoes the chosen tag on stdout; returns non-zero on cancel.
ui_menu() { # title body tag1 item1 tag2 item2 ...
  local title="$1" body="$2"; shift 2
  if [ "$HAVE_WHIPTAIL" = 1 ]; then
    whiptail --title "$title" --notags --menu "$body" 22 76 12 "$@" 3>&1 1>&2 2>&3
  else
    printf '\n== %s ==\n%s\n' "$title" "$body"
    local i=1 tags=()
    while [ $# -gt 0 ]; do tags+=("$1"); printf '  %d) %s\n' "$i" "$2"; shift 2; i=$((i+1)); done
    local sel; read -r -p "select #: " sel
    [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le "${#tags[@]}" ] || return 1
    printf '%s\n' "${tags[$((sel-1))]}"
  fi
}

# Show a scrollable text file / long output.
ui_textbox() { # title file
  if [ "$HAVE_WHIPTAIL" = 1 ]; then
    whiptail --title "$1" --scrolltext --textbox "$2" 24 78
  else
    printf '\n== %s ==\n' "$1"; cat "$2"; read -r -p "[enter] " _
  fi
}
