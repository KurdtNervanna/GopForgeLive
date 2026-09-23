# shellcheck shell=bash
# detect.sh — hardware discovery: Mac model + installed GPUs.
# Sourced by gopwizard.sh.

# Fill these arrays. Each GPU is described by parallel arrays indexed 0..N-1.
GFL_GPU_BDF=()     # PCI address, e.g. 0000:01:00.0
GFL_GPU_VENDOR=()  # 1002 (AMD) / 10de (NVIDIA)
GFL_GPU_DEVICE=()  # device id, e.g. 67df
GFL_GPU_SUBSYS=()  # subsystem id "svid:sdid", e.g. 1002:0b1e
GFL_GPU_NAME=()    # human name from lspci
GFL_MAC_MODEL=""   # e.g. MacPro5,1 / iMac12,2 (or "" if unknown / non-Mac)

detect_mac_model() {
  GFL_MAC_MODEL=""
  if command -v dmidecode >/dev/null 2>&1; then
    GFL_MAC_MODEL="$(dmidecode -s system-product-name 2>/dev/null | head -n1 | tr -d '\r')"
  fi
  # dmidecode can report generic strings on non-Apple boards; keep only Apple-ish.
  case "$GFL_MAC_MODEL" in
    MacPro*|iMac*|Macmini*|MacBook*) : ;;
    *) GFL_MAC_MODEL="" ;;
  esac
}

# Machine capability profile — decides which guided path a machine may use.
# Policy (per project design):
#   * Classic Mac Pro 4,1/5,1  -> BootROM EnableGop path only (dump/GopForge/flash),
#                                 NO guided GPU vBIOS flashing.
#   * Supported iMac 2009-2011 -> guided GPU vBIOS flashing only, NO BootROM path.
#   * MacPro3,1 and earlier / other models / non-Apple -> nothing (unsupported).
# Sets: GFL_MACHINE_CLASS  cmp-bootrom | imac-gpu | unsupported
#       GFL_ALLOW_BOOTROM / GFL_ALLOW_GPU  (0|1)
#       GFL_MACHINE_LABEL / GFL_MACHINE_NOTE
machine_profile() {
  detect_mac_model
  local m="$GFL_MAC_MODEL"
  GFL_MACHINE_CLASS="unsupported"; GFL_ALLOW_BOOTROM=0; GFL_ALLOW_GPU=0
  GFL_MACHINE_LABEL="${m:-non-Apple / unknown}"; GFL_MACHINE_NOTE=""
  case "$m" in
    MacPro4,1|MacPro5,1)
      GFL_MACHINE_CLASS="cmp-bootrom"; GFL_ALLOW_BOOTROM=1; GFL_ALLOW_GPU=0
      GFL_MACHINE_NOTE="Classic Mac Pro. Boot screen = inject EnableGop into the Mac BootROM (dump -> GopForge -> flash). Guided GPU vBIOS flashing is intentionally not offered here (use Expert override if a card needs GOP in its own vBIOS too)." ;;
    iMac9,1|iMac10,1|iMac11,1|iMac11,2|iMac11,3|iMac12,1|iMac12,2)
      GFL_MACHINE_CLASS="imac-gpu"; GFL_ALLOW_GPU=1; GFL_ALLOW_BOOTROM=0
      GFL_MACHINE_NOTE="Supported iMac (2009-2011). Boot screen = flash a GOP-enabled vBIOS onto the GPU. The BootROM/GopForge path is for Mac Pro only and is disabled here." ;;
    MacPro1,1|MacPro2,1|MacPro3,1)
      GFL_MACHINE_NOTE="$m is 32-bit-EFI / pre-GCN era — not supported by these boot-screen methods. Nothing to flash." ;;
    iMac*|MacPro*|Macmini*|MacBook*)
      GFL_MACHINE_NOTE="$m is outside the supported set (Mac Pro 4,1/5,1 and iMac 2009-2011). Guided flashing disabled." ;;
    "")
      GFL_MACHINE_NOTE="Not an Apple system, or the model could not be read. Guided flashing disabled; use Expert override only if you know exactly what you are doing." ;;
    *)
      GFL_MACHINE_NOTE="Unrecognized model ($m). Guided flashing disabled." ;;
  esac
}

# Populate the GFL_GPU_* arrays from lspci. Requires pciutils.
detect_gpus() {
  GFL_GPU_BDF=(); GFL_GPU_VENDOR=(); GFL_GPU_DEVICE=()
  GFL_GPU_SUBSYS=(); GFL_GPU_NAME=()
  command -v lspci >/dev/null 2>&1 || { warn "lspci not found (pciutils)"; return 1; }

  # Classes 0300 (VGA) and 0380 (other display) cover Mac GPUs.
  local line bdf rest
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    bdf="${line%% *}"
    rest="${line#* }"
    # Normalise to domain:bus:dev.fn
    [[ "$bdf" == *:*:* ]] || bdf="0000:$bdf"

    # -Dnnmm machine form gives: bdf "class" "vendor" "device" -rNN "svid" "sdid"
    local m ven dev svid sdid name
    m="$(lspci -Dnnmm -s "$bdf" 2>/dev/null | head -n1)"
    # Fields are quoted; pull the [id] bracket values which are stable.
    ven="$(sed -n 's/.*\[\([0-9a-fA-F]\{4\}\):[0-9a-fA-F]\{4\}\].*/\1/p' <<<"$m" | head -n1)"
    # Vendor/device from the non-machine form is easier to read for the name.
    name="$(lspci -Dnn -s "$bdf" 2>/dev/null | sed 's/^[^ ]* //')"
    ven="$(sed -n 's/.*\[\([0-9a-fA-F]\{4\}\):[0-9a-fA-F]\{4\}\]$/\1/p;s/.*\[\([0-9a-fA-F]\{4\}\):[0-9a-fA-F]\{4\}\] .*/\1/p' <<<"$name" | head -n1)"
    dev="$(sed -n 's/.*\[[0-9a-fA-F]\{4\}:\([0-9a-fA-F]\{4\}\)\]$/\1/p;s/.*\[[0-9a-fA-F]\{4\}:\([0-9a-fA-F]\{4\}\)\] .*/\1/p' <<<"$name" | head -n1)"
    # Subsystem id via verbose output.
    local sub
    sub="$(lspci -Dnn -s "$bdf" -v 2>/dev/null | sed -n 's/.*Subsystem:.*\[\([0-9a-fA-F]\{4\}:[0-9a-fA-F]\{4\}\)\].*/\1/p' | head -n1)"

    GFL_GPU_BDF+=("$bdf")
    GFL_GPU_VENDOR+=("$(tr 'A-F' 'a-f' <<<"${ven:-????}")")
    GFL_GPU_DEVICE+=("$(tr 'A-F' 'a-f' <<<"${dev:-????}")")
    GFL_GPU_SUBSYS+=("$(tr 'A-F' 'a-f' <<<"${sub:-????:????}")")
    GFL_GPU_NAME+=("${name:-unknown display controller}")
  done < <(lspci -D -d ::0300 2>/dev/null; lspci -D -d ::0380 2>/dev/null)

  [ "${#GFL_GPU_BDF[@]}" -gt 0 ]
}

gpu_vendor_label() { # vendorid
  case "$1" in
    1002) echo "AMD/ATI" ;;
    10de) echo "NVIDIA" ;;
    *)    echo "vendor $1" ;;
  esac
}

# Pretty multi-line report used by the "Detect hardware" screen.
detect_report() {
  detect_mac_model
  detect_gpus
  {
    echo "System model : ${GFL_MAC_MODEL:-<not an Apple system / unknown>}"
    echo "flashrom     : $(command -v flashrom >/dev/null 2>&1 && flashrom --version 2>/dev/null | head -n1 || echo 'missing')"
    echo "amdvbflash   : $(command -v amdvbflash >/dev/null 2>&1 && echo present || echo 'missing')"
    echo "nvflash      : $(command -v nvflash   >/dev/null 2>&1 && echo present || echo 'missing')"
    echo
    echo "Display adapters:"
    local i
    for i in "${!GFL_GPU_BDF[@]}"; do
      printf '  [%d] %s  (%s  %s:%s  subsys %s)\n' \
        "$i" "${GFL_GPU_NAME[$i]}" \
        "$(gpu_vendor_label "${GFL_GPU_VENDOR[$i]}")" \
        "${GFL_GPU_VENDOR[$i]}" "${GFL_GPU_DEVICE[$i]}" "${GFL_GPU_SUBSYS[$i]}"
    done
    [ "${#GFL_GPU_BDF[@]}" -gt 0 ] || echo "  (none detected)"
  }
}
