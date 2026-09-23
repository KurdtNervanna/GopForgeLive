# shellcheck shell=bash
# library.sh — map (iMac model + GPU) to candidate GOP ROMs from the
# IMAC-EFI-BOOT-SCREEN matrix, annotated for safety. Sourced by gopwizard.sh.

GFL_MATRIX="${GFL_MATRIX:-$GFL_ROOT/catalog/imac-boot-screen-matrix.json}"
GFL_INDEX="${GFL_INDEX:-$GFL_ROMS/index.json}"   # optional, from fetch-roms.sh

lib_ok() { command -v jq >/dev/null 2>&1 && [ -r "$GFL_MATRIX" ]; }

# Resolve a matrix rom path ("EG2/foo.rom") to an absolute file in the library.
resolve_rom() { # relfile
  local r="$1" p
  for p in "$GFL_ROMS/$r" "$GFL_ROMS/$(basename "$r")" "$r"; do
    [ -f "$p" ] && { echo "$p"; return 0; }
  done
  return 1
}

# Model profile from GFL_MAC_MODEL -> sets GFL_PANEL/GFL_DRIVER/GFL_FORBID/GFL_MODEL_NOTE.
model_profile() {
  GFL_PANEL="unknown"; GFL_DRIVER="any"; GFL_FORBID=""; GFL_MODEL_NOTE=""
  lib_ok || return 0
  local m="${GFL_MAC_MODEL:-}"
  [ -n "$m" ] || return 0
  local row
  row="$(jq -c --arg m "$m" '.model_rules[$m] // empty' "$GFL_MATRIX" 2>/dev/null)"
  [ -n "$row" ] || return 0
  GFL_PANEL="$(jq -r '.panel // "unknown"' <<<"$row")"
  GFL_DRIVER="$(jq -r '.driver // "any"' <<<"$row")"
  GFL_FORBID="$(jq -r '(.forbid_methods // []) | join(",")' <<<"$row")"
  GFL_MODEL_NOTE="$(jq -r '.note // ""' <<<"$row")"
}

# Find matrix cards for a detected GPU: device-id matches first, then name-glob
# matches, deduped. One compact JSON object per line (may be several — e.g. the
# shared Ellesmere 67df matches both RX470 and RX480, so the caller disambiguates).
matrix_find_cards() { # deviceid gpu_name
  lib_ok || return 1
  {
    [ -n "$1" ] && jq -c --arg d "$1" '
      .cards[] | select((.match.device // []) | map(ascii_downcase) | index($d|ascii_downcase))' \
      "$GFL_MATRIX" 2>/dev/null
    jq -c --arg n "$2" '
      ($n|ascii_downcase|gsub(" ";"")) as $nn
      | .cards[] | select((.match.name_globs // [])
        | map(. as $g | $nn | contains($g|ascii_downcase|gsub(" ";""))) | any)' \
      "$GFL_MATRIX" 2>/dev/null
  } | awk 'NF && !seen[$0]++'
}

# Suitability marker for one rom given the current model profile.
#   ✓ good   ⚠ caution   ✗ will not work
_rom_marker() { # method panel
  local method="$1" rpanel="$2"
  # forbidden method on this model (e.g. eg2 on iMac10,1 A1312)
  case ",$GFL_FORBID," in *",$method,"*) echo "✗ ${method^^} broken on this model"; return;; esac
  # iMac9,1 needs eg91
  if [ "$GFL_DRIVER" = eg91 ] && [ "$method" != eg91 ]; then echo "⚠ iMac9,1 wants EnableGop91"; return; fi
  if [ "$method" = eg91 ] && [ "$GFL_DRIVER" != eg91 ]; then echo "· EnableGop91 (only needed on iMac9,1)"; return; fi
  # panel mismatch
  if [ "$rpanel" = lvds ] && [ "$GFL_PANEL" = edp ]; then echo "· LVDS variant (eDP model — not needed)"; return; fi
  echo "✓ suitable"
}

# Emit whiptail menu pairs (tag=relfile, item=label) for a card's roms,
# ranked best-first for the current model. Only lists roms present in the library.
card_menu_items() { # cardjson  -> prints: <relfile>\n<label>\n ... (pairs)
  local card="$1"
  local lvds; lvds="$(jq -r '.lvds // "unknown"' <<<"$card")"
  # method rank: gop=0 eg2=1 eg91=1 eg=2 uga=3
  jq -r '.roms[] | [.file, (.method//""), (.panel//""), (.mem//""), (.vram//""), (.note//"")] | @tsv' <<<"$card" |
  while IFS=$'\t' read -r file method panel mem vram note; do
    local abs; abs="$(resolve_rom "$file" || true)"
    [ -n "$abs" ] || continue                        # skip roms not fetched
    local marker; marker="$(_rom_marker "$method" "$panel")"
    local rank=5
    case "$method" in gop) rank=0;; eg2) rank=1;; eg91) rank=1;; eg) rank=2;; uga) rank=3;; esac
    case "$marker" in ✗*) rank=$((rank+10));; ⚠*) rank=$((rank+5));; esac
    local extra=""
    [ -n "$mem" ]  && extra+=" mem:$mem"
    [ -n "$vram" ] && extra+=" vram:$vram"
    [ -n "$panel" ] && extra+=" $panel"
    [ -n "$note" ] && extra+=" ($note)"
    printf '%d\t%s\t%s\n' "$rank" "$file" "[${method^^}]$extra  $marker"
  done | sort -n | cut -f2-
}

# Full library browse (every rom on disk), for expert/manual selection.
library_all_items() { # -> pairs relfile / label
  [ -d "$GFL_ROMS" ] || return 1
  ( cd "$GFL_ROMS" && find . -type f -iname '*.rom' | sed 's#^\./##' | sort ) |
  while IFS= read -r f; do printf '%s\t%s\n' "$f" "$f"; done
}
