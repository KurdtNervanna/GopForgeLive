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

GFL_VERSION="0.1.0-untested"

# --- locate ourselves & libraries -------------------------------------------
GFL_BIN="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
GFL_ROOT="$(cd -- "$GFL_BIN/.." && pwd)"
GFL_LIB="$GFL_BIN/lib"

# ROM search root: EnableGop GCN4 set shipped by GRML-FLASH, or a user drop.
GFL_ROMS="${GFL_ROMS:-$GFL_ROOT/roms}"

# shellcheck source=lib/ui.sh
. "$GFL_LIB/ui.sh"
# workdir must exist before other libs log into it
. "$GFL_LIB/safety.sh"
GFL_WORKDIR="$(gfl_resolve_workdir)"
GFL_LOG="$GFL_WORKDIR/gopforge-live.log"
. "$GFL_LIB/detect.sh"
. "$GFL_LIB/catalog.sh"
. "$GFL_LIB/vbios.sh"
. "$GFL_LIB/bootrom.sh"

trap 'err "aborted (line $LINENO)"' ERR

banner() {
  cat <<EOF
${C_INFO}GopForge-Live${C_RESET} $GFL_VERSION
  working dir : $GFL_WORKDIR
  log         : $GFL_LOG
EOF
}

preflight() {
  require_root
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

flow_gpu_vbios() {
  local i; i="$(choose_gpu_index)" || return 0
  local ven="${GFL_GPU_VENDOR[$i]}" dev="${GFL_GPU_DEVICE[$i]}" sub="${GFL_GPU_SUBSYS[$i]}"
  local name="${GFL_GPU_NAME[$i]}"

  # Catalog recommendation
  local entry rom_rel rom_abs verified notes
  entry="$(catalog_match "$ven" "$dev" "$sub" || true)"
  if [ -n "$entry" ]; then
    rom_rel="$(catalog_field "$entry" rom)"
    verified="$(catalog_field "$entry" verified)"
    notes="$(catalog_field "$entry" notes)"
    rom_abs="$(catalog_rom_path "$rom_rel" || true)"
    ui_msg "Catalog match" \
"Card   : $name
ID     : $ven:$dev  subsys $sub
ROM    : ${rom_rel:-<none>}  ${rom_abs:+(found)}
Verified: ${verified:-false}
Notes  : ${notes:-none}"
  else
    ui_msg "No catalog match" \
"Card: $name ($ven:$dev subsys $sub)

No curated GOP vBIOS entry for this card. You can still flash a ROM
you place under $GFL_WORKDIR/video manually, but GopForge-Live will
not auto-recommend one."
    verified="false"
  fi

  # Only a verified catalog entry with a present ROM is offered for auto-flash.
  local rom=""
  if [ "${verified:-false}" = "true" ] && [ -n "${rom_abs:-}" ]; then
    ui_yesno "Use recommended ROM?" "Flash the verified GOP ROM:\n  $rom_rel\nonto $name?" \
      && rom="$rom_abs"
  fi
  if [ -z "$rom" ]; then
    warn "no verified auto-ROM selected; drop a .rom in $GFL_WORKDIR/video and re-run, or use expert CLI."
    ui_msg "Manual flash required" \
"For safety, auto-flash is limited to catalog entries marked verified.
Place your ROM under:
  $GFL_WORKDIR/video/
then flash from a shell with amdvbflash/nvflash (see docs/WORKFLOW.md)."
    return 0
  fi

  case "$ven" in
    1002)
      ui_textbox "AMD adapters" <(amd_list)
      local aidx; aidx="$(ui_menu "AMD adapter index" "Enter the amdvbflash adapter index for this card." 0 "index 0" 1 "index 1" 2 "index 2")" || return 0
      local backup; backup="$(amd_backup "$aidx")" || { ui_msg "Backup failed" "Not flashing."; return 0; }
      confirm_write "AMD vBIOS" "$name (adapter $aidx)" "backup: $backup" no || return 0
      if amd_flash "$aidx" "$rom" no; then
        ui_msg "Done" "AMD flash reported success. Power off fully before rebooting."
      else
        ui_msg "Flash failed" "See $GFL_LOG. Your backup is at:\n$backup"
      fi
      ;;
    10de)
      ui_textbox "NVIDIA adapters" <(nv_list)
      local nidx; nidx="$(ui_menu "NVIDIA index" "Enter the nvflash index for this card." 0 "index 0" 1 "index 1")" || return 0
      local backup; backup="$(nv_backup "$nidx")" || { ui_msg "Backup failed" "Not flashing."; return 0; }
      confirm_write "NVIDIA vBIOS" "$name (index $nidx)" "backup: $backup" no || return 0
      if nv_flash "$nidx" "$rom"; then
        ui_msg "Done" "NVIDIA flash reported success. Power off fully before rebooting."
      else
        ui_msg "Flash failed" "See $GFL_LOG. Your backup is at:\n$backup"
      fi
      ;;
    *) ui_msg "Unsupported" "No flasher for vendor $ven." ;;
  esac
}

# ============================================================================
# BootROM (EnableGop) path
# ============================================================================
flow_bootrom() {
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
  local c
  c="$(ui_menu "Read-only dumps" "Take a backup without flashing anything." \
    gpu "Save a GPU vBIOS" rom "Save the system BootROM" back "Back")" || return 0
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
  while true; do
    local c
    c="$(ui_menu "GopForge-Live $GFL_VERSION" \
"All-in-one GOP boot-screen flashing wizard.
Working dir: $GFL_WORKDIR" \
      detect "1) Detect hardware (report)" \
      gpu    "2) GPU vBIOS GOP flash" \
      rom    "3) Mac BootROM EnableGop (dump→patch→flash)" \
      dump   "4) Read-only backups" \
      log    "5) View log" \
      quit   "6) Quit")" || break
    case "$c" in
      detect) local t; t="$(mktemp)"; detect_report >"$t" 2>&1; ui_textbox "Hardware" "$t"; rm -f "$t" ;;
      gpu)    flow_gpu_vbios ;;
      rom)    flow_bootrom ;;
      dump)   flow_dumps ;;
      log)    [ -f "$GFL_LOG" ] && ui_textbox "Log" "$GFL_LOG" || ui_msg "Log" "empty" ;;
      quit)   break ;;
    esac
  done
}

# --- CLI --------------------------------------------------------------------
case "${1:-}" in
  --version) echo "$GFL_VERSION"; exit 0 ;;
  --detect)  preflight; detect_report; exit 0 ;;
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
main_menu
info "bye"
