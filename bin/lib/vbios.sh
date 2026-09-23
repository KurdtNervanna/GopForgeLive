# shellcheck shell=bash
# vbios.sh — GPU vBIOS backup + flash (AMD via amdvbflash, NVIDIA via nvflash).
# Every flash path here takes a mandatory verified backup first.
#
# GRML-FLASH ships amdvbflash/nvflash as binaries under <medium>/flash/video —
# NOT on PATH (its README runs them as ./amdvbflash). locate_flash_tools() finds
# them and stages them into a tmpfs (the FAT medium can mount noexec), setting
# GFL_AMDVBFLASH / GFL_NVFLASH. flashrom is a normal PATH install in GRML.

GFL_AMDVBFLASH="${GFL_AMDVBFLASH:-}"
GFL_NVFLASH="${GFL_NVFLASH:-}"
GFL_TOOLBIN="/tmp/gopforge-bin"

# Copy a tool into tmpfs and mark it executable; echo the staged path.
_stage_tool() { # srcpath
  local src="$1" dst
  [ -n "$src" ] && [ -f "$src" ] || return 1
  mkdir -p "$GFL_TOOLBIN" 2>/dev/null || return 1
  dst="$GFL_TOOLBIN/$(basename "$src")"
  cp -f "$src" "$dst" 2>/dev/null && chmod +x "$dst" 2>/dev/null && { echo "$dst"; return 0; }
  return 1
}

# Locate amdvbflash + nvflash on the live medium (or PATH) and stage them.
locate_flash_tools() {
  local vdir="" d found
  for d in /run/live/medium /lib/live/mount/medium /cdrom /live/image \
           /run/live/persistence/* /lib/live/mount/persistence/*; do
    [ -d "$d/flash/video" ] && { vdir="$d/flash/video"; break; }
  done
  if [ -z "$vdir" ]; then
    found="$(find /run/live /lib/live/mount /cdrom -maxdepth 6 -type f -iname 'amdvbflash*' 2>/dev/null | head -n1)"
    [ -n "$found" ] && vdir="$(dirname "$found")"
  fi

  # AMD: prefer the plain Linux binary, then the versioned one.
  if [ -z "$GFL_AMDVBFLASH" ]; then
    for found in "$vdir/amdvbflash" "$vdir"/amdvbflash-*; do
      [ -f "$found" ] && { GFL_AMDVBFLASH="$(_stage_tool "$found")" && break; }
    done
    [ -z "$GFL_AMDVBFLASH" ] && command -v amdvbflash >/dev/null 2>&1 && GFL_AMDVBFLASH="$(command -v amdvbflash)"
  fi
  # NVIDIA: prefer the Linux nvflash, then generic.
  if [ -z "$GFL_NVFLASH" ]; then
    for found in "$vdir/nvflash_linux" "$vdir/nvflash64" "$vdir/nvflash"; do
      [ -f "$found" ] && { GFL_NVFLASH="$(_stage_tool "$found")" && break; }
    done
    [ -z "$GFL_NVFLASH" ] && command -v nvflash >/dev/null 2>&1 && GFL_NVFLASH="$(command -v nvflash)"
  fi
  GFL_FLASHVIDEO_DIR="$vdir"
  [ -n "$GFL_AMDVBFLASH" ] || [ -n "$GFL_NVFLASH" ]
}

amd_present() { [ -n "$GFL_AMDVBFLASH" ] && [ -x "$GFL_AMDVBFLASH" ]; }
nv_present()  { [ -n "$GFL_NVFLASH" ]   && [ -x "$GFL_NVFLASH" ]; }

# --- AMD ---------------------------------------------------------------------
amd_list() { "$GFL_AMDVBFLASH" -i 2>&1; }

amd_backup() { # adapter_index
  amd_present || { err "amdvbflash not found on the medium"; return 1; }
  local idx="$1" dir out
  dir="$(gfl_backup_dir video/Backups)"
  out="$dir/amd-adapter${idx}-$(date +%Y%m%d-%H%M%S).rom"
  info "reading current AMD vBIOS (adapter $idx) …"
  "$GFL_AMDVBFLASH" -s "$idx" "$out" >/dev/null 2>&1 || { err "amdvbflash -s failed"; return 1; }
  verify_dump "$out" || return 1
  echo "$out"
}

amd_flash() { # adapter_index rom force(yes/no)
  amd_present || { err "amdvbflash not found on the medium"; return 1; }
  local idx="$1" rom="$2" force="${3:-no}"
  [ -f "$rom" ] || { err "ROM not found: $rom"; return 1; }
  info "flashing AMD adapter $idx with $(basename "$rom") …"
  if [ "$force" = yes ]; then "$GFL_AMDVBFLASH" -f -p "$idx" "$rom"
  else                        "$GFL_AMDVBFLASH"    -p "$idx" "$rom"; fi
  local rc=$?
  [ $rc -eq 0 ] && ok "amdvbflash reported success" || err "amdvbflash exit $rc"
  return $rc
}

# --- NVIDIA ------------------------------------------------------------------
nv_list() { "$GFL_NVFLASH" --list 2>&1; }

nv_backup() { # index
  nv_present || { err "nvflash not found on the medium"; return 1; }
  local idx="$1" dir out
  dir="$(gfl_backup_dir video/Backups)"
  out="$dir/nvidia-idx${idx}-$(date +%Y%m%d-%H%M%S).rom"
  info "reading current NVIDIA vBIOS (index $idx) …"
  "$GFL_NVFLASH" -i"$idx" --save "$out" >/dev/null 2>&1 || { err "nvflash --save failed"; return 1; }
  verify_dump "$out" || return 1
  echo "$out"
}

nv_flash() { # index rom
  nv_present || { err "nvflash not found on the medium"; return 1; }
  local idx="$1" rom="$2"
  [ -f "$rom" ] || { err "ROM not found: $rom"; return 1; }
  info "disabling write protect on index $idx …"
  "$GFL_NVFLASH" -i"$idx" --protectoff >/dev/null 2>&1 || warn "protectoff returned non-zero (may be fine)"
  info "flashing NVIDIA index $idx with $(basename "$rom") …"
  "$GFL_NVFLASH" -i"$idx" -6 "$rom"
  local rc=$?
  "$GFL_NVFLASH" -i"$idx" --protecton >/dev/null 2>&1 || true
  [ $rc -eq 0 ] && ok "nvflash reported success" || err "nvflash exit $rc"
  return $rc
}
