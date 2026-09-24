#!/usr/bin/env bash
# gopwizard.sh — GopForge-Live all-in-one GOP boot-screen wizard.
#
# One boot disk that:
#   * detects the Mac model and installed GPU(s)
#   * recommends a known-good GOP-enabled vBIOS from a curated catalog
#   * backs up and flashes the GPU vBIOS (amdvbflash / nvflash)
#   * dumps the Mac BootROM (flashrom), injects EnableGop (GopForge), flashes back
#
# Designed to run inside the GRML-FLASH live environment. It never writes to
# hardware without a verified backup and explicit confirmation.
#
# SPDX-License-Identifier: MIT
set -Eeuo pipefail

# --- locate ourselves & shared startup ----------------------------------------
GFL_BIN="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/bootstrap.sh
. "$GFL_BIN/lib/bootstrap.sh"

trap 'err "aborted (line $LINENO)"' ERR

banner() {
  cat <<EOF
${C_INFO}GopForge-Live${C_RESET} $GFL_VERSION
  working dir : $GFL_WORKDIR
  log         : $GFL_LOG
EOF
}

# Write a full snapshot to the log at startup, so even a session where the
# operator can't navigate leaves useful diagnostics on the USB.
log_startup() {
  machine_profile
  {
    echo "================ GopForge-Live session $(date 2>/dev/null) ================"
    echo "version : $GFL_VERSION"
    echo "cmdline : $(cat /proc/cmdline 2>/dev/null)"
    echo "medium  : ${GFL_MEDIUM:-<none>}   workdir: $GFL_WORKDIR   plain-menu: $([ "$HAVE_WHIPTAIL" = 1 ] && echo no || echo yes)"
    echo
    detect_report
    echo
    echo "machine class : $GFL_MACHINE_CLASS  (bootrom=$GFL_ALLOW_BOOTROM gpu=$GFL_ALLOW_GPU)"
    echo "$GFL_MACHINE_NOTE"
    echo "amdvbflash : ${GFL_AMDVBFLASH:-<not found>}"
    echo "nvflash    : ${GFL_NVFLASH:-<not found>}"
    echo "flashrom   : $(command -v flashrom 2>/dev/null || echo '<not found>')"
    echo "==========================================================================="
  } >>"$GFL_LOG" 2>&1
  sync 2>/dev/null || true
}

preflight() {
  require_root
  # Locate amdvbflash/nvflash on the GRML-FLASH medium (not on PATH) and stage them.
  locate_flash_tools || true
  [ -n "${GFL_TOOLBIN:-}" ] && [ -d "$GFL_TOOLBIN" ] && case ":$PATH:" in *":$GFL_TOOLBIN:"*) : ;; *) PATH="$GFL_TOOLBIN:$PATH";; esac
  local miss=()
  command -v lspci >/dev/null 2>&1 || miss+=("pciutils(lspci)")
  command -v flashrom >/dev/null 2>&1 || miss+=("flashrom")
  [ "${#miss[@]}" -eq 0 ] || warn "missing (some paths disabled): ${miss[*]}"
}

# ============================================================================
# GPU vBIOS path
# ============================================================================
choose_gpu_index() { # -> echoes chosen array index, or non-zero on cancel
  detect_gpus || { ui_msg "No GPU" "No display adapters detected by lspci."; return 1; }
  local args=() i
  for i in "${!GFL_GPU_BDF[@]}"; do
    args+=("$i" "$(gpu_vendor_label "${GFL_GPU_VENDOR[$i]}") ${GFL_GPU_DEVICE[$i]} — ${GFL_GPU_NAME[$i]}")
  done
  ui_menu "Select GPU" "Which adapter do you want to work on?" "${args[@]}"
}

# Backup the selected adapter's current vBIOS, confirm, then flash $rom.
do_gpu_flash() { # vendorid rom_abs gpu_name
  local ven="$1" rom="$2" name="$3"
  case "$ven" in
    1002)
      ui_textbox "AMD adapters (amdvbflash -i)" <(amd_list)
      local aidx; aidx="$(ui_menu "AMD adapter index" "Pick the amdvbflash adapter index for this card." 0 "index 0" 1 "index 1" 2 "index 2")" || return 0
      local backup; backup="$(amd_backup "$aidx")" || { ui_msg "Backup failed" "Not flashing."; return 0; }
      confirm_write "AMD vBIOS" "$name (adapter $aidx)" "rom: $(basename "$rom")\nbackup: $backup" no || return 0
      if amd_flash "$aidx" "$rom" no; then
        ui_msg "Done" "AMD flash reported success.\nPower OFF fully before rebooting.\nBackup: $backup"
      else
        ui_msg "Flash failed" "See $GFL_LOG. Restore with:\n  amdvbflash -f -p $aidx $backup"
      fi ;;
    10de)
      ui_textbox "NVIDIA adapters (nvflash --list)" <(nv_list)
      local nidx; nidx="$(ui_menu "NVIDIA index" "Pick the nvflash index for this card." 0 "index 0" 1 "index 1")" || return 0
      local backup; backup="$(nv_backup "$nidx")" || { ui_msg "Backup failed" "Not flashing."; return 0; }
      confirm_write "NVIDIA vBIOS" "$name (index $nidx)" "rom: $(basename "$rom")\nbackup: $backup" no || return 0
      if nv_flash "$nidx" "$rom"; then
        ui_msg "Done" "NVIDIA flash reported success.\nPower OFF fully before rebooting.\nBackup: $backup"
      else
        ui_msg "Flash failed" "See $GFL_LOG. Backup: $backup"
      fi ;;
    *) ui_msg "Unsupported" "No flasher for vendor $ven." ;;
  esac
}

# Browse the whole fetched ROM library and flash a chosen file (expert path).
browse_library_flash() { # vendorid gpu_name
  local ven="$1" name="$2"
  local items=(); local f l
  while IFS=$'\t' read -r f l; do items+=("$f" "$l"); done < <(library_all_items)
  [ "${#items[@]}" -gt 0 ] || { ui_msg "Empty library" "No ROMs under $GFL_ROMS. Run tools/fetch-roms.sh first."; return 0; }
  local pick; pick="$(ui_menu "ROM library" "Pick any ROM to flash (expert — verify it matches your card!)." "${items[@]}")" || return 0
  local abs; abs="$(resolve_rom "$pick")" || { ui_msg "Not found" "$pick"; return 0; }
  do_gpu_flash "$ven" "$abs" "$name"
}

flow_gpu_vbios() {
  if [ "${GFL_ALLOW_GPU:-0}" != 1 ] && [ "${GFL_EXPERT:-0}" != 1 ]; then
    ui_msg "Not available here" "Guided GPU vBIOS flashing is offered on supported iMacs (2009-2011).
Detected: ${GFL_MACHINE_LABEL:-unknown}."; return 0; fi
  local i; i="$(choose_gpu_index)" || return 0
  local ven="${GFL_GPU_VENDOR[$i]}" dev="${GFL_GPU_DEVICE[$i]}" sub="${GFL_GPU_SUBSYS[$i]}"
  local name="${GFL_GPU_NAME[$i]}"

  detect_mac_model
  # Resolve models dmidecode can't disambiguate (e.g. iMac10,1 A1311 vs A1312).
  GFL_MODEL_KEY="$GFL_MAC_MODEL"
  if model_ambiguous; then
    local vitems=() vk vlbl
    while IFS=$'\t' read -r vk vlbl; do [ -n "$vk" ] && vitems+=("$vk" "$vlbl"); done < <(model_variant_items)
    if [ "${#vitems[@]}" -gt 0 ]; then
      local chosen; chosen="$(ui_menu "Which $GFL_MAC_MODEL exactly?" \
"dmidecode reports only \"$GFL_MAC_MODEL\", which covers different panels that need
different ROMs. Pick your exact model:" "${vitems[@]}")" && GFL_MODEL_KEY="$chosen"
    fi
  fi
  model_profile

  if ! lib_ok; then
    ui_msg "Matrix unavailable" "jq or the ROM matrix is missing; opening the raw library browser."
    browse_library_flash "$ven" "$name"; return 0
  fi

  local cards=(); local cj
  while IFS= read -r cj; do [ -n "$cj" ] && cards+=("$cj"); done < <(matrix_find_cards "$dev" "$name")
  local card=""
  if [ "${#cards[@]}" -eq 0 ]; then
    ui_yesno "No matrix match" \
"Model : ${GFL_MAC_MODEL:-unknown} (panel: $GFL_PANEL)
GPU   : $name ($ven:$dev)

No matrix entry matched this card. Browse the full ROM library and
pick manually?" defaultyes && browse_library_flash "$ven" "$name"
    return 0
  elif [ "${#cards[@]}" -eq 1 ]; then
    card="${cards[0]}"
  else
    # Ambiguous (e.g. shared device id 67df = RX470/RX480/570/580) — let the user pick.
    local args=() k
    for k in "${!cards[@]}"; do args+=("$k" "$(jq -r '.name' <<<"${cards[$k]}")"); done
    local sel; sel="$(ui_menu "Which card exactly?" \
"$ven:$dev matches several boards (shared device id). Pick the one you have." "${args[@]}")" || return 0
    card="${cards[$sel]}"
  fi

  local cname; cname="$(jq -r '.name' <<<"$card")"
  local cnotes; cnotes="$(jq -r '.notes // ""' <<<"$card")"
  ui_msg "Matched: $cname" \
"Model : ${GFL_MODEL_KEY:-$GFL_MAC_MODEL}  (panel: $GFL_PANEL, driver: $GFL_DRIVER)
GPU   : $name ($ven:$dev)
${GFL_MODEL_NOTE:+Model note: $GFL_MODEL_NOTE
}${cnotes:+Card note : $cnotes}

Next screen ranks the ROMs for this card:
  ✓ suitable   ⚠ caution   ✗ won't work on this model
✗ ROMs (a method known-broken on this model, e.g. EG2 on iMac10,1 A1312)
are BLOCKED unless the Expert override is on."

  # Build the ranked candidate menu.
  local items=(); local f l
  while IFS=$'\t' read -r f l; do items+=("$f" "$l"); done < <(card_menu_items "$card")
  items+=("__BROWSE__" "» Browse the entire ROM library instead")
  local pick; pick="$(ui_menu "ROMs for $cname" "Choose a ROM to flash." "${items[@]}")" || return 0

  if [ "$pick" = "__BROWSE__" ]; then browse_library_flash "$ven" "$name"; return 0; fi

  # Hard-block a ROM whose method the model_rule forbids (e.g. EG2 white-screens
  # on iMac10,1 A1312). Expert override bypasses.
  local pmethod; pmethod="$(rom_method_of "$card" "$pick")"
  if [ -n "$GFL_FORBID" ] && [ -n "$pmethod" ] && [ "${GFL_EXPERT:-0}" != 1 ]; then
    case ",$GFL_FORBID," in *",$pmethod,"*)
      ui_msg "Blocked for this model" \
"${pmethod^^} is known-broken on ${GFL_MODEL_KEY:-$GFL_MAC_MODEL}
(e.g. EG2 gives a white screen on the iMac10,1 A1312 27\").

Pick a GOP or EG ROM instead. (This block can only be bypassed via the
Expert override on the main menu.)"
      return 0 ;;
    esac
  fi

  local abs; abs="$(resolve_rom "$pick")" || { ui_msg "Not found" "$pick — run tools/fetch-roms.sh."; return 0; }
  do_gpu_flash "$ven" "$abs" "$name"
}

# ============================================================================
# BootROM (EnableGop) path
# ============================================================================
flow_bootrom() {
  if [ "${GFL_ALLOW_BOOTROM:-0}" != 1 ] && [ "${GFL_EXPERT:-0}" != 1 ]; then
    ui_msg "Not available here" "The BootROM / GopForge path applies to classic Mac Pro 4,1/5,1 only.
Detected: ${GFL_MACHINE_LABEL:-unknown}."; return 0; fi
  bootrom_tools_ok || { ui_msg "Missing tools" "flashrom/perl/GopForge not all present. See docs/INSTALL.md and tools/fetch-vendor.sh."; return 0; }
  detect_mac_model
  ui_yesno "BootROM EnableGop" \
"Detected system: ${GFL_MAC_MODEL:-<unknown / non-Apple>}

This will:
  1. dump the system BootROM (flashrom)
  2. let GopForge identify + inject EnableGop
  3. write the patched BootROM back (flashrom)

Flashing the BootROM can brick the machine. A CH341A hardware
recovery path is strongly recommended (docs/RECOVERY.md). Continue?" \
    || return 0

  local dump; dump="$(bootrom_dump)" || { ui_msg "Dump failed" "See $GFL_LOG."; return 0; }

  local checkout; checkout="$(mktemp)"; bootrom_check "$dump" >"$checkout" 2>&1 || true
  ui_textbox "GopForge --check" "$checkout"; rm -f "$checkout"

  # GopForge itself refuses non-4,1/5,1 images on --inject, so we can offer it.
  local variant
  variant="$(ui_menu "EnableGop variant" \
"standard = most GPUs with real GOP in their vBIOS.
direct   = GPUs needing DirectGopRendering (e.g. some Vega)." \
    standard "Standard EnableGop" direct "EnableGopDirect")" || return 0

  local patched; patched="$(bootrom_inject "$dump" "$variant")" \
    || { ui_msg "Injection failed" "See $GFL_LOG. Nothing was written to hardware."; return 0; }

  confirm_write "Mac BootROM" "${GFL_MAC_MODEL:-BootROM} ($GFL_FLASHROM_PROG)" \
    "backup: $dump\npatched: $patched" yes || { ui_msg "Cancelled" "Backup kept at $dump."; return 0; }

  local rc=0; bootrom_chip_matches "$dump" || rc=$?
  if [ "$rc" -ne 0 ]; then
    ui_msg "Not written" \
"$( [ "$rc" -eq 1 ] && echo "The Boot ROM changed since the backup was taken (NVRAM is written by the
firmware), so the patched image is out of date. Nothing was written —
run this again to take a fresh backup and patch." || echo "Re-reading the Boot ROM failed, so nothing was written. See $GFL_LOG." )"
    return 0
  fi

  if bootrom_write "$patched"; then
    ui_msg "Done" \
"BootROM written. Power OFF fully (not just reboot).

Test: hold ⌥ (Option) at power-on for the native picker. On a non-native
GPU the screen may stay black until the picker — that can still be success.
If nothing appears, the GPU likely needs GOP in its vBIOS too (GPU path).
Backup: $dump"
  else
    ui_msg "Write failed" \
"flashrom reported a write error. The BootROM may be unchanged (Apple SPI
lock) or partially written. DO NOT power off if a re-flash is running.
See docs/RECOVERY.md. Backup: $dump"
  fi
}

# ============================================================================
# Read-only helpers
# ============================================================================
flow_dumps() {
  local ab="${GFL_ALLOW_BOOTROM:-0}" ag="${GFL_ALLOW_GPU:-0}"
  [ "${GFL_EXPERT:-0}" = 1 ] && { ab=1; ag=1; }
  local args=()
  [ "$ag" = 1 ] && args+=( gpu "Save a GPU vBIOS" )
  [ "$ab" = 1 ] && args+=( rom "Save the system BootROM" )
  args+=( back "Back" )
  local c
  c="$(ui_menu "Read-only dumps" "Take a backup without flashing anything." "${args[@]}")" || return 0
  case "$c" in
    gpu)
      local i; i="$(choose_gpu_index)" || return 0
      case "${GFL_GPU_VENDOR[$i]}" in
        1002) local x; x="$(ui_menu "AMD index" "adapter index" 0 0 1 1 2 2)" && amd_backup "$x" >/dev/null && ui_msg "Saved" "See $GFL_WORKDIR/video/Backups";;
        10de) local x; x="$(ui_menu "NV index" "index" 0 0 1 1)" && nv_backup "$x" >/dev/null && ui_msg "Saved" "See $GFL_WORKDIR/video/Backups";;
        *) ui_msg "Unsupported" "vendor ${GFL_GPU_VENDOR[$i]}";;
      esac ;;
    rom)
      bootrom_tools_ok && { local d; d="$(bootrom_dump)" && ui_msg "Saved" "$d"; } || ui_msg "Missing" "flashrom not available." ;;
  esac
}

# ============================================================================
main_menu() {
  machine_profile
  GFL_EXPERT="${GFL_EXPERT:-0}"
  while true; do
    # Effective allowances (expert override unlocks everything).
    local ab="$GFL_ALLOW_BOOTROM" ag="$GFL_ALLOW_GPU"
    [ "$GFL_EXPERT" = 1 ] && { ab=1; ag=1; }

    local args=( detect "Detect hardware (full report)" )
    [ "$ag" = 1 ] && args+=( gpu "GPU vBIOS GOP flash (guided)" )
    [ "$ab" = 1 ] && args+=( rom "Mac BootROM EnableGop (dump→patch→flash)" )
    { [ "$ag" = 1 ] || [ "$ab" = 1 ]; } && args+=( dump "Read-only backups" )
    if [ "$GFL_ALLOW_BOOTROM" = 0 ] && [ "$GFL_ALLOW_GPU" = 0 ]; then
      if [ "$GFL_EXPERT" = 1 ]; then args+=( expert "Expert override: ON — disable it" )
      else                          args+=( expert "Expert override: unlock paths anyway" ); fi
    fi
    args+=( log "View log" quit "Quit" )

    local gate
    if   [ "$ag" = 1 ] && [ "$GFL_MACHINE_CLASS" = imac-gpu ]; then gate="→ guided GPU vBIOS flashing"
    elif [ "$ab" = 1 ] && [ "$GFL_MACHINE_CLASS" = cmp-bootrom ]; then gate="→ BootROM EnableGop (GopForge)"
    elif [ "$GFL_EXPERT" = 1 ]; then gate="→ EXPERT: all paths unlocked (gating ignored)"
    else gate="→ no guided actions for this machine"; fi

    local c
    c="$(ui_menu "GopForge-Live $GFL_VERSION" \
"Machine: $GFL_MACHINE_LABEL  [$GFL_MACHINE_CLASS]
$gate

$GFL_MACHINE_NOTE" "${args[@]}")" || break
    case "$c" in
      detect) local t; t="$(mktemp)"; { detect_report; echo; echo "Machine class: $GFL_MACHINE_CLASS (bootrom=$GFL_ALLOW_BOOTROM gpu=$GFL_ALLOW_GPU expert=$GFL_EXPERT)"; echo "$GFL_MACHINE_NOTE"; } >"$t" 2>&1; ui_textbox "Hardware" "$t"; rm -f "$t" ;;
      gpu)    flow_gpu_vbios ;;
      rom)    flow_bootrom ;;
      dump)   flow_dumps ;;
      expert)
        if [ "$GFL_EXPERT" = 1 ]; then GFL_EXPERT=0; warn "expert override disabled"
        elif ui_yesno "Enable expert override?" \
"This machine ($GFL_MACHINE_LABEL) is not a supported target, so guided flashing
is disabled for your safety.

Expert override unlocks BOTH the GPU vBIOS and BootROM paths regardless of the
detected machine. Flashing the wrong target can permanently brick hardware and
there is no guided safety net. Only continue if you know exactly what you are
doing. Enable?"; then GFL_EXPERT=1; warn "EXPERT OVERRIDE ENABLED"; fi ;;
      log)    [ -f "$GFL_LOG" ] && ui_textbox "Log" "$GFL_LOG" || ui_msg "Log" "empty" ;;
      quit)   break ;;
    esac
  done
}

# --- CLI --------------------------------------------------------------------
case "${1:-}" in
  --version) echo "$GFL_VERSION"; exit 0 ;;
  --detect)  preflight; detect_report; machine_profile
             echo; echo "Machine class: $GFL_MACHINE_CLASS (bootrom=$GFL_ALLOW_BOOTROM gpu=$GFL_ALLOW_GPU)"
             echo "$GFL_MACHINE_NOTE"; exit 0 ;;
  --help|-h)
    cat <<EOF
GopForge-Live $GFL_VERSION
Usage: sudo gopwizard.sh [--detect|--version|--help]
  (no args)  launch the interactive wizard
  --detect   print a hardware report and exit
Docs: docs/WORKFLOW.md, docs/RECOVERY.md
EOF
    exit 0 ;;
esac

banner
preflight
log_startup
main_menu
info "bye"; sync 2>/dev/null || true
