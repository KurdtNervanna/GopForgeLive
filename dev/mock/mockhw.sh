#!/usr/bin/env bash
# mockhw.sh — simulated Mac hardware for developing/demoing the GUI safely.
# NOTHING here touches real hardware. Selected via environment:
#   GFL_MOCK_MODEL  dmidecode product name   (default MacPro5,1; "PC" = non-Apple)
#   GFL_MOCK_GPU    comma list of GPUs: vega64 rx580 wx7100 wx4150 m6100 gtx680 qemu none
#   GFL_MOCK_FAIL   dump | write | backup | flash   → make that step fail
#   GFL_MOCK_PATCHED=1  the simulated BootROM already contains EnableGop
#   GFL_MOCK_FAST=1     skip the realistic delays
#   GFL_MOCK_DRIFT=1    every Boot ROM read changes one NVRAM byte (stale-backup test)
#   GFL_MOCK_LOCKED=1   Boot ROM write-protected like a cMP outside flash mode
#   GFL_MOCK_CHIP       file holding the simulated chip (writes persist; default
#                       $GFL_MEDIUM/.mock-chip.rom, else /tmp)
# Usage (via the wrapper scripts in dev/mock/bin): mockhw.sh <tool> [args…]
set -u
tool="$1"; shift
FIX="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/fixtures"
nap() { [ "${GFL_MOCK_FAST:-0}" = 1 ] || sleep "$1"; }
CHIP="${GFL_MOCK_CHIP:-${GFL_MEDIUM:-/tmp}/.mock-chip.rom}"
fail_on() { case ",${GFL_MOCK_FAIL:-}," in *",$1,"*) return 0;; esac; return 1; }

gpu_line() { # profile -> "bdf|lspci -Dnn text (no bdf)|subsys|amd-product|kind"
  case "$1" in
    vega64) echo "0000:0b:00.0|VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Vega 10 XL/XT [Radeon RX Vega 56/64] [1002:687f] (rev c1)|1002:0b36|Vega10 D0501 XTX A1 HBM2 8GB|amd" ;;
    rx580)  echo "0000:0c:00.0|VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Ellesmere [Radeon RX 470/480/570/570X/580/580X/590] [1002:67df] (rev e7)|1da2:e366|Ellesmere Polaris20 XTX GDDR5 8GB|amd" ;;
    wx7100) echo "0000:01:00.0|VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Ellesmere [Radeon Pro WX 7100 Mobile] [1002:67c0] (rev 00)|1028:17b1|Ellesmere D0120 MXM GDDR5 8GB|amd" ;;
    wx4150) echo "0000:01:00.0|VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Baffin [Radeon Pro WX 4150] [1002:67e8] (rev 00)|106b:0000|Baffin D0911 MXM GDDR5 4GB|amd" ;;
    m6100)  echo "0000:01:00.0|VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Saturn XT [FirePro M6100] [1002:6640] (rev 00)|106b:014b|Saturn XT MXM GDDR5 2GB|amd" ;;
    gtx680) echo "0000:03:00.0|VGA compatible controller [0300]: NVIDIA Corporation GK104 [GeForce GTX 680] [10de:1180] (rev a1)|106b:010d|GTX 680 Mac Edition|nvidia" ;;
    qemu)   echo "0000:00:01.0|VGA compatible controller [0300]: Device [1234:1111] (rev 02)|1af4:1100|QEMU std VGA|other" ;;
  esac
}
gpus() { local g; for g in ${GFL_MOCK_GPU//,/ }; do [ "$g" = none ] || gpu_line "$g"; done; }

make_bootrom() { # out  — a 4 MiB image that looks like a cMP 4,1/5,1 BootROM
  perl -e '
    my ($out,$patched)=@ARGV; my $d="\xFF" x 4194304;
    srand(51); my $blob=join("",map{chr(int(rand(256)))} 1..(0x3A0000-0x150048));
    substr($d,0x150048,length($blob))=$blob;                       # DXE drivers
    substr($d,0x150000,0x48)=("\x00" x 32).pack("Q<",0x290000)."_FVH".("\x00" x 28); # DXE FV header (as on MP51)
    substr($d,0x1A0000,16)=pack("H*","9f59e7ba6b3cb743bdf09ce07aa91aa6"); # cMP anchor
    substr($d,0x180000,16)=pack("H*","b158ba3fc0f8bc41acd8253043a3a17f") if $patched;
    open(my $fh,">:raw",$out) or die $!; print $fh $d;' "$1" "${GFL_MOCK_PATCHED:-0}"
}

case "$tool" in
  dmidecode)
    model="${GFL_MOCK_MODEL:-MacPro5,1}"
    fixture="$FIX/${model%%-*}.dmi"
    if [[ " $* " == *" -t "* ]]; then          # SMBIOS tables from the fixture, filtered by type
      [ -f "$fixture" ] || exit 0
      want=""; prev=""
      for a in "$@"; do
        if [ "$prev" = -t ]; then
          case "$a" in bios) want+=" 0";; system) want+=" 1";; baseboard) want+=" 2";; chassis) want+=" 3";;
                        processor) want+=" 4";; memory) want+=" 16 17";; *) want+=" $a";; esac
        fi
        prev="$a"
      done
      awk -v want="$want " '/^Handle /{ split($0, f, "type "); t = f[2] + 0; keep = index(want, " " t " ") > 0 }
                           /^Handle /, /^$/ { if (keep) print }' "$fixture"
      exit 0
    fi
    [ "$model" = PC ] && { echo "Standard PC (Q35 + ICH9, 2009)"; exit 0; }
    echo "$model" ;;

  lspci)
    args="$*"; sel=""
    [[ "$args" =~ -s[[:space:]]+([^[:space:]]+) ]] && sel="${BASH_REMATCH[1]}"
    fixture="$FIX/${GFL_MOCK_MODEL:-MacPro5,1}.pci"
    if [ -z "$sel" ] && [[ "$args" != *" -d "* ]] && [[ "$args" != -d* ]]; then   # full device list (hardware report)
      [ -f "$fixture" ] && cat "$fixture"
      while IFS='|' read -r bdf text sub prod kind; do
        [ -n "$bdf" ] || continue
        echo "$bdf $text"; echo "	Subsystem: Device [$sub]"
        case "$kind" in amd) echo "	Kernel driver in use: amdgpu";; nvidia) echo "	Kernel driver in use: nouveau";; esac
      done < <(gpus)
      exit 0
    fi
    while IFS='|' read -r bdf text sub prod kind; do
      [ -n "$bdf" ] || continue
      if [ -z "$sel" ]; then
        case "$args" in *::0300*) echo "$bdf ${text%% \[*}: ${text#*: }" ;; esac
      elif [ "$sel" = "$bdf" ]; then
        echo "$bdf $text"
        case "$args" in *-v*) echo "	Subsystem: Apple Inc. Device [$sub]"; echo "	Flags: bus master, fast devsel, latency 0, IRQ 42";; esac
      fi
    done < <(gpus) ;;

  lsusb)
    fixture="$FIX/${GFL_MOCK_MODEL:-MacPro5,1}.usb"
    [ "${1:-}" = -t ] && exit 0
    [ -f "$fixture" ] && cat "$fixture" ;;

  flashrom)
    case "$*" in
      *--version*|*-v\ *) echo "flashrom v1.3.0 (mock) on Linux 6.6.15-amd64 (x86_64)"; exit 0 ;;
    esac
    file=""; mode=""
    while [ $# -gt 0 ]; do case "$1" in -r) mode=r; file="$2"; shift 2;; -w) mode=w; file="$2"; shift 2;; *) shift;; esac; done
    echo "flashrom v1.3.0 (mock) on Linux 6.6.15-amd64 (x86_64)"
    echo "Using clock_gettime for delay loops (clk_id: 1, resolution: 1ns)."; nap 0.6
    echo "Found chipset \"Intel ICH10R\"."
    if [ "${GFL_MOCK_LOCKED:-0}" = 1 ]; then      # what a cMP prints outside flash mode
      echo "Enabling flash write... SPI Configuration is locked down."
      echo "PR0: Warning: 0x00000000-0x0011ffff is read-only."
      echo "PR1: Warning: 0x00150000-0x01ffffff is read-only."
      echo "At least some flash regions are write protected. For write operations,"
      echo "you should use a flash layout and include only writable regions. See"
      echo "manpage for more details."
      echo "OK."
    else
      echo "Enabling flash write... OK."
    fi
    nap 0.6
    echo "Found SST flash chip \"SST25VF032B\" (4096 kB, SPI) mapped at physical address 0x00000000ffc00000."
    if [ "$mode" = r ]; then
      echo "Reading flash..."; nap 3
      fail_on dump && { echo "Transaction error!"; echo "Read operation failed!"; exit 1; }
      if [ -f "$CHIP" ]; then cp "$CHIP" "$file"; else make_bootrom "$file"; fi
      if [ "${GFL_MOCK_DRIFT:-0}" = 1 ]; then    # NVRAM moves on between reads
        n=$(( $(cat "$CHIP.drift" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$CHIP.drift"
        printf "\x$(printf %02x $(( n % 256 )))" | dd of="$file" bs=1 seek=$((0x120100)) conv=notrunc status=none
      fi
      echo "done."
    elif [ "$mode" = w ]; then
      echo "Reading old flash chip contents... done."; nap 1.5
      echo "Erasing and writing flash chip..."; nap 5
      { fail_on write || [ "${GFL_MOCK_LOCKED:-0}" = 1 ]; } && { echo "Transaction error!"; echo "FAILED at 0x001a0000! Expected=0x9f, Found=0xff"; exit 1; }
      cp "$file" "$CHIP"
      echo "Erase/write done."; echo "Verifying flash..."; nap 2; echo "VERIFIED."
    fi ;;

  amdvbflash)
    case "${1:-}" in
      -i)
        echo "adapter seg bus dev fun DID  RID SSID SSVID Product Name"
        echo "======= === === === === ==== === ==== ===== ================================="
        i=0; while IFS='|' read -r bdf text sub prod kind; do
          [ "$kind" = amd ] || continue
          did="$(grep -oE '\[1002:[0-9a-f]{4}\]' <<<"$text" | cut -c7-10 | tr a-f A-F)"
          bus="${bdf:5:2}"
          printf '   %-4s %s  %s   00   0  %s C1  %s %s  %s\n' "$i" 00 "$bus" "$did" "$(cut -d: -f2 <<<"$sub" | tr a-f A-F)" "$(cut -d: -f1 <<<"$sub" | tr a-f A-F)" "$prod"
          i=$((i+1))
        done < <(gpus) ;;
      -s)
        echo "AMDVBFLASH version 4.71, Copyright (c) 2020 Advanced Micro Devices, Inc."; nap 1.5
        fail_on backup && { echo "ERROR: 0FL01 Adapter not found"; exit 1; }
        head -c 262144 /dev/urandom > "$3"; printf 'PCIR' | dd of="$3" bs=1 seek=512 conv=notrunc 2>/dev/null
        echo "Old SSID: 0B36"; echo "Old P/N: 113-D0501100-102"; echo "ROM contents saved to $3" ;;
      -p|-f)
        [ "$1" = -f ] && shift
        echo "AMDVBFLASH version 4.71, Copyright (c) 2020 Advanced Micro Devices, Inc."; nap 1
        echo "Old SSID: 0B36"; echo "New SSID: 0B36"; echo "Old P/N: 113-D0501100-102"; echo "New P/N: 113-EnableGop-GOP"
        echo "Erasing ROM..."; nap 2; echo "Programming ROM..."; nap 3
        fail_on flash && { echo "ERROR: 0FL04 ROM verification failed"; exit 1; }
        echo "Verifying ROM..."; nap 1; echo "Restart System To Complete VBIOS Update." ;;
    esac ;;

  nvflash)
    case "$*" in
      *--list*) i=0; while IFS='|' read -r bdf text sub prod kind; do
                  [ "$kind" = nvidia ] || continue
                  echo "<$i> (10DE,1180,$(tr a-f A-F <<<"${sub/:/,}")) S:00,B:${bdf:5:2},D:00,F:00"; i=$((i+1))
                done < <(gpus) ;;
      *--save*) out="${!#}"; echo "NVIDIA Firmware Update Utility (Version 5.590.0)"; nap 1.5
                fail_on backup && { echo "ERROR: No NVIDIA display adapters found"; exit 1; }
                head -c 131072 /dev/urandom > "$out"; echo "Firmware image saved to $out" ;;
      *--protectoff*|*--protecton*) echo "Setting EEPROM software protect setting... OK" ;;
      *-6*) echo "NVIDIA Firmware Update Utility (Version 5.590.0)"; nap 1
            echo "Checking for matches between display adapter(s) and image(s)..."; nap 1
            echo "Updating firmware on display adapter..."; nap 4
            fail_on flash && { echo "ERROR: Firmware image verification failed"; exit 1; }
            echo "Update successful." ;;
    esac ;;
  *) echo "mockhw: unknown tool $tool" >&2; exit 127 ;;
esac
