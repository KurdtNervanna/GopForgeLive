# shellcheck shell=bash
# safety.sh — backup, verification and confirmation helpers.
# Nothing in GopForge-Live writes to hardware without going through here.

# Find the USB's own FAT partition as it is mounted READ-WRITE in the live system.
# GRML-FLASH boots with `persistence`, so live-boot mounts the stick rw under
# /run/live/persistence/<dev> (e.g. sdb1). NOTE: /run/live/medium is NOT a mount
# on GRML-FLASH — just an empty dir in the RAM overlay — so writes there vanish at
# power-off. We only accept real mountpoints that look like GRML-FLASH (flash/ or
# live/ present). Must be called in the main shell (not in $(...)) by the caller.
GFL_MEDIUM="${GFL_MEDIUM:-}"
gfl_find_usb() {
  local m
  for m in /run/live/persistence/* /lib/live/mount/persistence/*            /usr/lib/live/mount/persistence/* /run/live/medium /lib/live/mount/medium; do
    [ -d "$m" ] || continue
    mountpoint -q "$m" 2>/dev/null || continue
    { [ -d "$m/flash" ] || [ -d "$m/live" ] || [ -d "$m/gopforge-live" ]; } || continue
    [ -w "$m" ] || mount -o remount,rw "$m" 2>/dev/null || true
    echo "$m"; return 0
  done
  return 1
}

# Working dir for the log + backups: on the USB when we can write there (so you
# can read them on any computer afterwards), else $HOME, else /tmp (RAM-only).
gfl_resolve_workdir() {
  local d
  for d in       "${GFL_MEDIUM:+$GFL_MEDIUM/gopforge-live}"       "${GFL_USB_MNT:-}"/gopforge-live       "${HOME:-/root}/gopforge-live"; do
    [ -n "$d" ] || continue
    [ "$d" = "/gopforge-live" ] && continue          # empty GFL_USB_MNT
    case "$d" in *'*'*) continue;; esac
    if mkdir -p "$d" 2>/dev/null && [ -w "$d" ]; then echo "$d"; return 0; fi
  done
  mkdir -p /tmp/gopforge-live 2>/dev/null
  echo /tmp/gopforge-live
}

gfl_backup_dir() { # subdir (e.g. video/Backups or firmware/Backups)
  local d="${GFL_WORKDIR:?workdir unset}/$1"
  mkdir -p "$d" 2>/dev/null || die "cannot create backup dir $d"
  echo "$d"
}

sha256_of() { # file
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  elif command -v shasum   >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  else echo "no-sha256-tool"; fi
}

file_size() { # file  -> bytes
  stat -c '%s' "$1" 2>/dev/null || stat -f '%z' "$1" 2>/dev/null || echo 0
}

# Verify a freshly written dump looks sane: exists, non-empty, and (optionally)
# matches an expected exact size. Returns 0 on success.
verify_dump() { # file [expected_bytes]
  local f="$1" want="${2:-}"
  [ -s "$f" ] || { err "dump $f is missing or empty"; return 1; }
  local got; got="$(file_size "$f")"
  if [ -n "$want" ] && [ "$got" != "$want" ]; then
    err "dump $f is $got bytes, expected $want"; return 1
  fi
  ok "dump verified: $f ($got bytes, sha256 $(sha256_of "$f" | cut -c1-16)…)"
  return 0
}

# The universal "are you really sure" gate before any destructive write.
# Requires the user to read a summary and confirm twice for boot ROMs.
confirm_write() { # what target extra_warning double(yes/no)
  local what="$1" target="$2" warning="$3" dbl="${4:-no}"
  ui_yesno "Confirm flash: $what" \
"About to WRITE:
  target : $target
  $warning

A mismatched image can permanently brick this hardware.
A verified backup must already exist. Proceed?" || return 1
  if [ "$dbl" = "yes" ]; then
    ui_yesno "FINAL confirmation" \
"This is the point of no return for:
  $target

Type-through this last prompt only if your backup is safe and you
have a hardware recovery path (see docs/RECOVERY.md). Continue?" || return 1
  fi
  return 0
}

require_root() {
  [ "$(id -u 2>/dev/null || echo 1)" = "0" ] || die "must run as root (sudo)."
}
