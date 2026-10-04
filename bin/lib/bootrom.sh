# shellcheck shell=bash
# bootrom.sh — Mac system BootROM path: flashrom dump -> GopForge inject -> write.
# This is the OS-independent equivalent of Macschrauber's Rom Dump + GopForge,
# doing all three stages on the live USB.

GFL_GOPFORGE="${GFL_GOPFORGE:-$GFL_ROOT/vendor/gopforge/gopforge.sh}"
# Where the cached EnableGop.ffs / EnableGopDirect.ffs / DXEInject live (put there
# by tools/fetch-vendor.sh). Passed to GopForge via --tools-dir so it resolves them
# no matter what CWD the wizard runs from.
GFL_GOPFORGE_TOOLS="${GFL_GOPFORGE_TOOLS:-$(dirname "$GFL_GOPFORGE")/tools}"

# dosdude1's DXEInject is a macOS binary, so the USB carries a Linux build of the
# same operation on the same engine (UEFITool 0.28 FfsEngine) — see
# tools/dxeinject-linux/. Built into vendor/ by tools/dxeinject-linux/build.sh.
GFL_DXEINJECT_DIR="${GFL_DXEINJECT_DIR:-$GFL_ROOT/vendor/dxeinject-linux}"

# flashrom programmer for in-system Mac SPI. cMP/iMac use the internal PCH SPI.
GFL_FLASHROM_PROG="${GFL_FLASHROM_PROG:-internal}"

# --- 144.0.0.0.0 rebuild / 4,1 -> 5,1 crossflash --------------------------------
# Borowski's Boot ROM templates (MacRumors "Guide: How to rebuild/update Mac Pro 4.1/5.1
# bootrom with template files"). Not redistributed: the operator copies templates.zip
# (or the .bin from it) into gopforge-live/templates/ on the USB. Pinned by SHA-256.
GFL_TEMPLATE_DIR="${GFL_TEMPLATE_DIR:-$GFL_WORKDIR/templates}"
GFL_TEMPLATE_URL="https://forums.macrumors.com/threads/guide-how-to-rebuild-update-mac-pro-4-1-5-1-bootrom-with-template-files.2437082/"
GFL_TEMPLATE_ZIP_SHA="eb65c5e313a76797071522f0dfd0f0be5a3c678393613234421be5e975d7e21d"
GFL_TEMPLATE_BIN_SHA="936077fabf6b123ac37754a318150570e9069c04f7c681374125e91064f6ea20"   # v144.0.0.0.0_template.bin
GFL_TEMPLATE_NAME="v144.0.0.0.0_template.bin"
GFL_REBUILD_PY="$GFL_LIB/bootrom_rebuild.py"

# Echo the path of a verified 144.0.0.0.0 template (extracting it from templates.zip
# into /tmp when that is what's on the USB). Fails when none is found.
template_find() {
  local f sha out="/tmp/gopforge-bin/$GFL_TEMPLATE_NAME"
  [ -f "$out" ] && [ "$(sha256_of "$out")" = "$GFL_TEMPLATE_BIN_SHA" ] && { echo "$out"; return 0; }
  for f in "$GFL_TEMPLATE_DIR"/*.bin "$GFL_TEMPLATE_DIR"/*.zip "${GFL_MEDIUM:-/nonexistent}"/templates.zip; do
    [ -f "$f" ] || continue
    sha="$(sha256_of "$f")"
    case "$sha" in
      "$GFL_TEMPLATE_BIN_SHA") echo "$f"; return 0 ;;
      "$GFL_TEMPLATE_ZIP_SHA")
        mkdir -p "$(dirname "$out")"
        python3 -c 'import sys, zipfile; open(sys.argv[3], "wb").write(zipfile.ZipFile(sys.argv[1]).read(sys.argv[2]))' \
          "$f" "$GFL_TEMPLATE_NAME" "$out" 2>/dev/null || continue
        [ "$(sha256_of "$out")" = "$GFL_TEMPLATE_BIN_SHA" ] && { echo "$out"; return 0; }
        rm -f "$out" ;;
    esac
  done
  return 1
}

# Rebuild <dump> on the template. Echoes the new image path; the JSON report from
# bootrom_rebuild.py goes to the log (and to $GFL_REBUILD_REPORT when set).
bootrom_rebuild() { # dump
  local dump="$1" tpl out rep rc=0
  tpl="$(template_find)" || { err "no verified 144.0.0.0.0 template in $GFL_TEMPLATE_DIR"; return 3; }
  out="${dump%.rom}-144.rom"
  info "rebuilding $(basename "$dump") on the 144.0.0.0.0 template …"
  rep="$(python3 "$GFL_REBUILD_PY" rebuild "$tpl" "$dump" "$out")" || rc=$?
  printf '%s\n' "$rep" >>"$GFL_LOG"
  [ -n "${GFL_REBUILD_REPORT:-}" ] && printf '%s\n' "$rep" >"$GFL_REBUILD_REPORT"
  if [ "$rc" -ne 0 ]; then
    rm -f "$out"; err "rebuild refused: $(sed -n 's/.*"error": "\([^"]*\)".*/\1/p' <<<"$rep")"; return "$rc"
  fi
  verify_dump "$out" "$(file_size "$dump")" || { rm -f "$out"; return 1; }
  ok "rebuilt image: $(basename "$out") — serial, Gaid and MAC/LBSN block carried over, checksums valid"
  echo "$out"
}

# Is <image> exactly the rebuild of <dump> (optionally plus EnableGop, which may only
# change the DXE volume)? Recomputes the rebuild from scratch and compares.
bootrom_is_rebuild_of() { # image dump
  local image="$1" dump="$2" tpl tmp rc=1
  tpl="$(template_find)" || return 1
  tmp="$(mktemp /tmp/gfl-rebuild-XXXXXX.rom)"
  if python3 "$GFL_REBUILD_PY" rebuild "$tpl" "$dump" "$tmp" >/dev/null 2>&1; then
    if cmp -s "$tmp" "$image"; then rc=0
    elif bootrom_changes_confined "$tmp" "$image" >/dev/null; then rc=0
    fi
  fi
  rm -f "$tmp"
  return "$rc"
}

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

# flashrom's report from the most recent chip read: it states the SPI protected
# ranges (PRx) the firmware set at boot, which decide whether a write can work.
GFL_FLASHROM_REPORT="${GFL_FLASHROM_REPORT:-/tmp/gopforge-bin/flashrom-last.txt}"

# Run a (short) flashrom read; output goes to the log, the terminal and the report.
_flashrom_read() { # args…
  local rc=0
  mkdir -p "$(dirname "$GFL_FLASHROM_REPORT")"
  flashrom --programmer "$GFL_FLASHROM_PROG" "$@" >"$GFL_FLASHROM_REPORT" 2>&1 || rc=$?
  tee -a "$GFL_LOG" <"$GFL_FLASHROM_REPORT" >"$GFL_TTY" 2>/dev/null || true
  return "$rc"
}

# Dump the system BootROM. Echoes the dump path on success.
bootrom_dump() {
  local dir out
  dir="$(gfl_backup_dir firmware/Backups)"
  out="$dir/bootrom-$(date +%Y%m%d-%H%M%S).rom"
  info "reading system BootROM via flashrom ($GFL_FLASHROM_PROG) …"
  if ! _flashrom_read -r "$out"; then
    err "flashrom read failed — see $GFL_LOG"; return 1
  fi
  verify_dump "$out" || return 1
  echo "$out"
}

# Write-protected ranges from the last flashrom report, one "start end" (decimal,
# inclusive) per line. A failed write-enable counts as the whole chip.
bootrom_wp_ranges() {
  local r="$GFL_FLASHROM_REPORT" a b
  [ -f "$r" ] || return 0
  if grep -qiE 'Enabling flash write\.\.\. *FAILED|Setting Bios Control .* failed' "$r"; then
    echo "0 4294967295"
  fi
  sed -nE 's/.*PR[0-9]+: Warning: 0x([0-9a-fA-F]+)-0x([0-9a-fA-F]+) is (read-only|locked).*/\1 \2/p' "$r" |
  while read -r a b; do echo "$((16#$a)) $((16#$b))"; done
}

# "start length" of the firmware volume holding the EnableGop insertion point —
# the only region a patch (or restoring its backup) rewrites.
bootrom_dxe_range() { # rom
  perl -e '
    my ($f,$anchor)=@ARGV; local $/;
    open(my $fh,"<:raw",$f) or exit 2; my $x=<$fh>;
    my $p = index($x, pack("H*",$anchor)); exit 4 if $p < 0;
    my $h = rindex($x, "_FVH", $p);          exit 4 if $h < 40;
    my $vs = $h - 40; my $vl = unpack("Q<", substr($x, $vs+32, 8));
    exit 4 if $vl == 0 || $vs + $vl > length($x) || $p >= $vs + $vl;
    printf "%d %d\n", $vs, $vl;' "$1" "9f59e7ba6b3cb743bdf09ce07aa91aa6"
}

# Would writing <rom> hit a write-protected range (per the last flashrom report)?
# 0 = blocked (echoes the blocking ranges as hex), 1 = the region is writable.
bootrom_write_blocked() { # rom [whole]  — "whole": the write may touch the entire chip
  local s l e a b hit=1 range
  if [ "${2:-}" != whole ] && range="$(bootrom_dxe_range "$1")"; then
    read -r s l <<<"$range"; e=$(( s + l - 1 ))
  else
    s=0; e=$(( $(file_size "$1") - 1 ))           # unknown layout: the whole image
  fi
  while read -r a b; do
    [ -n "$a" ] || continue
    if [ "$a" -le "$e" ] && [ "$b" -ge "$s" ]; then
      printf '0x%06X-0x%06X\n' "$a" "$b"; hit=0
    fi
  done < <(bootrom_wp_ranges)
  return "$hit"
}

# Shared operator guidance when the chip is locked.
GFL_FLASH_MODE_HELP="Shut down, then press and hold the power button until the Mac beeps (flash mode) and release it. Boot this USB again (hold Option, pick EFI Boot) and do Back Up, Patch and Flash in that session — NVRAM changes on every start, so a fresh backup is needed."

# Run GopForge --check on a dump and return its human report (also to the log).
bootrom_check() { # dump
  info "GopForge inspecting $(basename "$1") …"
  bash "$GFL_GOPFORGE" --check "$1" 2>&1 | tee -a "$GFL_LOG"
}

# Echo the path of a Linux DXEInject that actually runs here. A FAT USB keeps no
# exec bits, so it is staged to /tmp first when needed.
linux_dxeinject() {
  local src="$GFL_DXEINJECT_DIR" dst="/tmp/gopforge-bin/dxeinject-linux" rc=0
  [ -f "$src/dxeinject.bin" ] || return 1
  if [ ! -x "$src/dxeinject" ] || [ ! -x "$src/dxeinject.bin" ]; then
    if [ ! -x "$dst/dxeinject.bin" ]; then
      mkdir -p "$dst" && cp -a "$src/." "$dst/" && chmod +x "$dst/dxeinject" "$dst/dxeinject.bin" || return 1
    fi
    src="$dst"
  fi
  "$src/dxeinject" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 64 ] || return 1          # its usage exit = binary + libs load fine
  echo "$src/dxeinject"
}

# Were ALL changes between the original dump and the patched image made inside
# the one firmware volume that holds the EnableGop insertion point? Everything
# else — NVRAM, serial/board data, boot block, microcode — must be byte-identical.
# Echoes "start length" of that volume. Fails closed on anything unexpected.
bootrom_changes_confined() { # original patched
  perl -e '
    my ($a,$b,$anchor)=@ARGV; local $/;
    open(my $fa,"<:raw",$a) or exit 2; my $x=<$fa>;
    open(my $fb,"<:raw",$b) or exit 2; my $y=<$fb>;
    exit 3 if length($x) != length($y);
    my $p = index($x, pack("H*",$anchor)); exit 4 if $p < 0;
    my $h = rindex($x, "_FVH", $p);          exit 4 if $h < 40;
    my $vs = $h - 40; my $vl = unpack("Q<", substr($x, $vs+32, 8));
    exit 4 if $vl == 0 || $vs + $vl > length($x) || $p >= $vs + $vl;
    exit 5 if substr($x, 0, $vs) ne substr($y, 0, $vs);
    exit 5 if substr($x, $vs+$vl) ne substr($y, $vs+$vl);
    printf "%d %d\n", $vs, $vl;' "$1" "$2" "9f59e7ba6b3cb743bdf09ce07aa91aa6"
}

# Inject EnableGop. variant = standard|direct. Echoes the output ROM path.
bootrom_inject() { # dump variant
  local dump="$1" variant="${2:-standard}" out inj range
  out="${dump%.rom}-enablegop.rom"
  local -a args=(--inject "$dump" -o "$out" -y --tools-dir "$GFL_GOPFORGE_TOOLS")
  [ "$variant" = direct ] && args+=(--direct)
  if inj="$(linux_dxeinject)"; then
    args+=(--dxeinject "$inj")
  else
    warn "Linux DXEInject not found on this USB — GopForge will look for its own copy"
  fi
  info "GopForge injecting EnableGop ($variant) …"
  if ! bash "$GFL_GOPFORGE" "${args[@]}" >>"$GFL_LOG" 2>&1; then
    err "GopForge injection failed — see $GFL_LOG"; rm -f "$out"; return 1
  fi
  # GopForge guarantees size-invariance; re-check against the source size.
  verify_dump "$out" "$(file_size "$dump")" || { rm -f "$out"; return 1; }
  if ! range="$(bootrom_changes_confined "$dump" "$out")"; then
    err "the patched image changed bytes outside the DXE volume — discarded"; rm -f "$out"; return 1
  fi
  set -- $range
  ok "changes confined to the DXE volume at $(printf '0x%X' "$1") ($(( $2 / 1024 )) KiB); NVRAM and boot block untouched"
  echo "$out"
}

# Read the chip into a temp file (not a backup). Echoes the path.
bootrom_read_tmp() {
  local tmp; tmp="$(mktemp /tmp/gfl-chip-XXXXXX.rom)"
  if ! _flashrom_read -r "$tmp"; then
    rm -f "$tmp"; err "flashrom read failed — see $GFL_LOG"; return 1
  fi
  echo "$tmp"
}

# Is the chip still byte-identical to <backup>? A patched image is built from that
# backup, so if the chip changed since (the firmware and OSes write NVRAM), writing
# the image would roll those changes back. 0 = matches, 1 = changed, 2 = read failed.
bootrom_chip_matches() { # backup
  local cur
  info "re-reading the Boot ROM to confirm it still matches $(basename "$1") …"
  cur="$(bootrom_read_tmp)" || return 2
  if cmp -s "$cur" "$1"; then
    rm -f "$cur"; ok "the chip still matches your backup"; return 0
  fi
  rm -f "$cur"; err "the Boot ROM has changed since $(basename "$1") was taken"; return 1
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
