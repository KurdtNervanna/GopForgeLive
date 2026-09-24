# shellcheck shell=bash
# bootrom.sh — Mac system BootROM path: flashrom dump -> GopForge inject -> write.
# This is the OS-independent equivalent of Macschrauber's Rom Dump + GopForge,
# doing all three stages on the live USB.

GFL_GOPFORGE="${GFL_GOPFORGE:-$GFL_ROOT/vendor/gopforge/gopforge.sh}"
# Where the cached EnableGop.ffs / EnableGopDirect.ffs / DXEInject live (put there
# by tools/fetch-vendor.sh). Passed to GopForge via --tools-dir so it resolves them
# no matter what CWD the wizard runs from.
GFL_GOPFORGE_TOOLS="${GFL_GOPFORGE_TOOLS:-$(dirname "$GFL_GOPFORGE")/tools}"

# flashrom programmer for in-system Mac SPI. cMP/iMac use the internal PCH SPI.
GFL_FLASHROM_PROG="${GFL_FLASHROM_PROG:-internal}"

bootrom_tools_ok() {
  command -v flashrom >/dev/null 2>&1 || { err "flashrom missing"; return 1; }
  [ -x "$GFL_GOPFORGE" ] || [ -f "$GFL_GOPFORGE" ] || { err "gopforge.sh not found at $GFL_GOPFORGE (run tools/fetch-vendor.sh)"; return 1; }
  command -v perl >/dev/null 2>&1 || { err "perl missing (GopForge needs it)"; return 1; }
  # Soft check: warn if the EnableGop tooling isn't cached (injection would then
  # need network, which a field USB usually lacks).
  [ -f "$GFL_GOPFORGE_TOOLS/EnableGop.ffs" ] || [ -f "$GFL_GOPFORGE_TOOLS/EnableGopDirect.ffs" ] \
    || warn "no cached EnableGop.ffs in $GFL_GOPFORGE_TOOLS — injection will need network (run tools/fetch-vendor.sh before building the USB)"
  return 0
}

# Dump the system BootROM. Echoes the dump path on success.
# NOTE: on some Macs Apple SPI protected-range/descriptor locks can block the
# write-back even when the read succeeds — see docs/RECOVERY.md.
bootrom_dump() {
  local dir out
  dir="$(gfl_backup_dir firmware/Backups)"
  out="$dir/bootrom-$(date +%Y%m%d-%H%M%S).rom"
  info "reading system BootROM via flashrom ($GFL_FLASHROM_PROG) …"
  if ! _run_logged flashrom --programmer "$GFL_FLASHROM_PROG" -r "$out"; then
    err "flashrom read failed — see $GFL_LOG"; return 1
  fi
  verify_dump "$out" || return 1
  echo "$out"
}

# Run GopForge --check on a dump and return its human report (also to the log).
bootrom_check() { # dump
  info "GopForge inspecting $(basename "$1") …"
  bash "$GFL_GOPFORGE" --check "$1" 2>&1 | tee -a "$GFL_LOG"
}

# Inject EnableGop. variant = standard|direct. Echoes the output ROM path.
bootrom_inject() { # dump variant
  local dump="$1" variant="${2:-standard}" out flag=""
  out="${dump%.rom}-enablegop.rom"
  [ "$variant" = direct ] && flag="--direct"
  info "GopForge injecting EnableGop ($variant) …"
  if ! bash "$GFL_GOPFORGE" --inject "$dump" -o "$out" $flag -y \
        --tools-dir "$GFL_GOPFORGE_TOOLS" >>"$GFL_LOG" 2>&1; then
    err "GopForge injection failed — see $GFL_LOG"; return 1
  fi
  # GopForge guarantees size-invariance; re-check against the source size.
  verify_dump "$out" "$(file_size "$dump")" || return 1
  echo "$out"
}

# Write a patched BootROM back with flashrom, then verify.
bootrom_write() { # patched_rom
  local rom="$1"
  [ -f "$rom" ] || { err "patched ROM not found: $rom"; return 1; }
  info "writing BootROM via flashrom (this can take a minute) …"
  if ! _run_logged flashrom --programmer "$GFL_FLASHROM_PROG" -w "$rom"; then
    err "flashrom write failed — see $GFL_LOG (BootROM may be unchanged; check RECOVERY.md)"; return 1
  fi
  ok "flashrom write + verify completed"
  return 0
}
