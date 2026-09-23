# shellcheck shell=bash
# vbios.sh — GPU vBIOS backup + flash (AMD via amdvbflash, NVIDIA via nvflash).
# Every flash path here takes a mandatory verified backup first.

# --- AMD ---------------------------------------------------------------------
# amdvbflash uses its own adapter index (not the PCI BDF). List them.
amd_list() { amdvbflash -i 2>&1; }

# Save current vBIOS. Echoes the backup path on success.
amd_backup() { # adapter_index
  local idx="$1" dir out
  dir="$(gfl_backup_dir video/Backups)"
  out="$dir/amd-adapter${idx}-$(date +%Y%m%d-%H%M%S).rom"
  info "reading current AMD vBIOS (adapter $idx) …"
  amdvbflash -s "$idx" "$out" >/dev/null 2>&1 || { err "amdvbflash -s failed"; return 1; }
  verify_dump "$out" || return 1
  echo "$out"
}

# Flash a new vBIOS. force=yes adds -f (older/forced writes). Assumes a backup
# was already taken and confirmed by the caller.
amd_flash() { # adapter_index rom force(yes/no)
  local idx="$1" rom="$2" force="${3:-no}"
  [ -f "$rom" ] || { err "ROM not found: $rom"; return 1; }
  info "flashing AMD adapter $idx with $(basename "$rom") …"
  if [ "$force" = yes ]; then amdvbflash -f -p "$idx" "$rom"
  else                        amdvbflash    -p "$idx" "$rom"; fi
  local rc=$?
  [ $rc -eq 0 ] && ok "amdvbflash reported success" || err "amdvbflash exit $rc"
  return $rc
}

# --- NVIDIA ------------------------------------------------------------------
nv_list() { nvflash --list 2>&1 || nvflash64 --list 2>&1; }

nv_bin() { command -v nvflash >/dev/null 2>&1 && echo nvflash || echo nvflash64; }

nv_backup() { # index
  local idx="$1" dir out nv; nv="$(nv_bin)"
  dir="$(gfl_backup_dir video/Backups)"
  out="$dir/nvidia-idx${idx}-$(date +%Y%m%d-%H%M%S).rom"
  info "reading current NVIDIA vBIOS (index $idx) …"
  "$nv" -i"$idx" --save "$out" >/dev/null 2>&1 || { err "nvflash --save failed"; return 1; }
  verify_dump "$out" || return 1
  echo "$out"
}

nv_flash() { # index rom
  local idx="$1" rom="$2" nv; nv="$(nv_bin)"
  [ -f "$rom" ] || { err "ROM not found: $rom"; return 1; }
  info "disabling write protect on index $idx …"
  "$nv" -i"$idx" --protectoff >/dev/null 2>&1 || warn "protectoff returned non-zero (may be fine)"
  info "flashing NVIDIA index $idx with $(basename "$rom") …"
  "$nv" -i"$idx" -6 "$rom"
  local rc=$?
  "$nv" -i"$idx" --protecton >/dev/null 2>&1 || true
  [ $rc -eq 0 ] && ok "nvflash reported success" || err "nvflash exit $rc"
  return $rc
}
