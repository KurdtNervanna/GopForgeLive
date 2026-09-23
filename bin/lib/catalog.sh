# shellcheck shell=bash
# catalog.sh — match a detected GPU to a known-good GOP vBIOS entry.
# The catalog is deliberately conservative: only entries flagged
# "verified": true are ever auto-recommended for flashing. Everything else is
# shown for reference and requires the manual/expert path.

GFL_CATALOG="${GFL_CATALOG:-$GFL_ROOT/catalog/gpu-gop-catalog.json}"

catalog_available() {
  command -v jq >/dev/null 2>&1 && [ -r "$GFL_CATALOG" ]
}

# Echo a JSON object (the matching entry) or nothing. Match order:
#   1. exact vendor:device + subsystem
#   2. vendor:device only (marked as a looser match by the caller)
catalog_match() { # vendorid deviceid subsys(svid:sdid)
  catalog_available || return 1
  local ven="$1" dev="$2" sub="$3"
  local hit
  hit="$(jq -c --arg v "$ven" --arg d "$dev" --arg s "$sub" '
    .cards[] | select((.vendor|ascii_downcase)==($v|ascii_downcase)
                   and (.device|ascii_downcase)==($d|ascii_downcase)
                   and ((.subsystems // []) | map(ascii_downcase) | index($s|ascii_downcase)))' \
    "$GFL_CATALOG" 2>/dev/null | head -n1)"
  if [ -z "$hit" ]; then
    hit="$(jq -c --arg v "$ven" --arg d "$dev" '
      .cards[] | select((.vendor|ascii_downcase)==($v|ascii_downcase)
                     and (.device|ascii_downcase)==($d|ascii_downcase))' \
      "$GFL_CATALOG" 2>/dev/null | head -n1)"
  fi
  [ -n "$hit" ] || return 1
  printf '%s\n' "$hit"
}

catalog_field() { # json field
  jq -r --arg f "$2" '.[$f] // empty' <<<"$1" 2>/dev/null
}

# Resolve the ROM path shipped with the disk. Catalog stores a relative name;
# real ROMs live under $GFL_ROMS (the EnableGop GCN4 set from GRML-FLASH, or a
# user drop). Returns absolute path or empty.
catalog_rom_path() { # rom_relname
  local r="$1"
  [ -n "$r" ] || return 1
  local p
  for p in "$GFL_ROMS/$r" "$GFL_WORKDIR/video/$r" "$r"; do
    [ -f "$p" ] && { echo "$p"; return 0; }
  done
  return 1
}
