# shellcheck shell=bash
# storage.sh — where the log, reports and firmware backups live, and "Save to USB"
# for sessions whose boot medium can't be written (the DVD, or a stick whose data
# partition isn't writable).
#
# Booted from the USB stick: everything goes to <USB>/gopforge-live (safety.sh).
# Otherwise the workdir is a fixed path whose target changes:
#   $GFL_RUN_DIR/work  →  $GFL_RUN_DIR/ram                 memory only
#                      →  <USB drive>/gopforge-live         after Save to USB
# Every path the app already handed out stays valid when the link moves.

GFL_RUN_DIR="${GFL_RUN_DIR:-/run/gopforge-live}"
GFL_SAVE_MNT_ROOT="${GFL_SAVE_MNT_ROOT:-/run/gopforge-save}"
GFL_SAVE_FS="vfat exfat ntfs ntfs3 ext2 ext3 ext4 hfsplus"

# The RAM workdir link (created on first use). A link left pointing at a drive that
# has gone away falls back to RAM.
gfl_ram_workdir() {
  local w="$GFL_RUN_DIR/work"
  mkdir -p "$GFL_RUN_DIR/ram" 2>/dev/null || return 1
  if [ ! -L "$w" ] || [ ! -d "$w/" ] || [ ! -w "$w/" ]; then
    rm -rf "$w" 2>/dev/null
    ln -sfn "$GFL_RUN_DIR/ram" "$w" || return 1
    rm -f "$GFL_RUN_DIR/drive.json"
  fi
  echo "$w"
}

# usb (the boot stick) | drive (saved to a USB drive) | ram (memory only)
gfl_storage_kind() {
  if [ "${GFL_WORKDIR:-}" = "$GFL_RUN_DIR/work" ]; then
    [ "$(readlink -f -- "$GFL_WORKDIR")" = "$(readlink -f -- "$GFL_RUN_DIR/ram")" ] && echo ram || echo drive
  elif [ -n "${GFL_MEDIUM:-}" ] || [ -n "${GFL_USB_MNT:-}" ]; then echo usb
  else echo ram
  fi
}
gfl_storage_persistent() { [ "$(gfl_storage_kind)" != ram ]; }

# Files in RAM that were never copied to a drive (relative paths, one per line).
gfl_unsaved_files() {
  local ram="$GFL_RUN_DIR/ram" rel h
  [ -d "$ram" ] || return 0
  (cd "$ram" && find . -type f ! -name gopforge-live.log -printf '%P\n' 2>/dev/null) | while IFS= read -r rel; do
    h="$(sha256_of "$ram/$rel")"
    grep -qxF "$h $rel" "$GFL_RUN_DIR/saved.list" 2>/dev/null || echo "$rel"
  done
}

# Whole disks the live system was booted from (never offered as save targets).
gfl_boot_disks() {
  local src m
  for m in /run/live/medium /lib/live/mount/medium /run/live/persistence/* /lib/live/mount/persistence/*; do
    src="$(findmnt -rn -o SOURCE --target "$m" 2>/dev/null | head -n1)" || continue
    case "$src" in /dev/*) lsblk -no PKNAME "$src" 2>/dev/null | head -n1; basename "$src" ;; esac
  done | sort -u | tr '\n' ' '
}

# USB drives the files can be saved to, as a JSON array.
gfl_save_targets() {
  if [ "${GFL_MOCK:-0}" = 1 ]; then         # GFL_MOCK_DRIVES="sdc1:vfat:LABEL:bytes:model,…"
    local e rows="[]" name fs label size model
    local -a list; IFS=',' read -ra list <<<"${GFL_MOCK_DRIVES:-}"
    for e in "${list[@]}"; do
      IFS=: read -r name fs label size model <<<"$e"
      [ -n "$name" ] || continue
      rows="$(jq -c --arg n "$name" --arg f "$fs" --arg l "$label" --arg s "${size:-0}" --arg m "$model" \
        --arg mp "$( [ -d "$GFL_SAVE_MNT_ROOT/$name" ] && echo "$GFL_SAVE_MNT_ROOT/$name" || true)" \
        '. + [{dev:("/dev/"+$n), name:$n, fstype:$f, label:$l, size:($s|tonumber), model:$m, mountpoint:$mp}]' <<<"$rows")"
    done
    echo "$rows"; return 0
  fi
  lsblk -J -b -o NAME,PATH,SIZE,FSTYPE,LABEL,TRAN,HOTPLUG,RO,TYPE,MOUNTPOINT,MODEL,PARTTYPE 2>/dev/null |
    jq -c --arg fs "$GFL_SAVE_FS" --arg boot "$(gfl_boot_disks)" '
      def yes: . == true or . == "1" or . == 1;
      ($fs | split(" ")) as $ok | ($boot | split(" ") | map(select(. != ""))) as $skip
      | [ .blockdevices[]? | . as $d
          | select(($d.tran == "usb") or ($d.hotplug | yes))
          | select(($skip | index($d.name)) | not)
          | (if ($d.children | length) > 0 then $d.children[] else $d end)
          | select(.type == "part" or .type == "disk")
          | select((.fstype // "") as $f | $ok | index($f))
          | select(((.ro | yes) or ($d.ro | yes)) | not)
          | select(((.parttype // "") | ascii_downcase) != "c12a7328-f81f-11d2-ba4b-00a0c93ec93b")   # EFI system partition
          | select((.label == "EFI" and .fstype == "vfat") | not)
          | {dev:.path, name:.name, fstype:.fstype, label:(.label // ""), size:((.size // 0) | tonumber),
             model:(($d.model // "") | gsub("^\\s+|\\s+$"; "")), mountpoint:(.mountpoint // "")} ]' 2>/dev/null || echo "[]"
}

# Mount a save target read-write (or reuse its mount); prints the mountpoint.
gfl_save_mount() { # dev fstype
  local dev="$1" fs="$2" mp cur
  if [ "${GFL_MOCK:-0}" = 1 ]; then
    mp="$GFL_SAVE_MNT_ROOT/$(basename "$dev")"; mkdir -p "$mp" && echo "$mp"; return
  fi
  cur="$(findmnt -rn -S "$dev" -o TARGET 2>/dev/null | head -n1)"
  if [ -n "$cur" ]; then
    mp="$cur"
    [ -w "$mp" ] || mount -o remount,rw "$mp" 2>/dev/null || true
  else
    mp="$GFL_SAVE_MNT_ROOT/$(basename "$dev")"
    mkdir -p "$mp" || return 1
    case "$fs" in
      vfat)       mount -t vfat -o rw,noatime,flush "$dev" "$mp" ;;
      ntfs|ntfs3) mount -t ntfs3 -o rw "$dev" "$mp" 2>/dev/null || ntfs-3g "$dev" "$mp" ;;
      *)          mount -t "$fs" -o rw "$dev" "$mp" ;;
    esac 2>&1 | sed 's/^/  mount: /' >&2
    mountpoint -q "$mp" || { rmdir "$mp" 2>/dev/null; return 1; }
  fi
  # Journaled Mac (HFS+) drives, and failing sticks, come up read-only.
  ( : >"$mp/.gopforge-write-test" ) 2>/dev/null && rm -f "$mp/.gopforge-write-test" || { echo "$mp"; return 2; }
  echo "$mp"
}

# Copy the RAM workdir into dest, verifying every file; then point the workdir there.
# Prints "copied skipped renamed" counts.
gfl_save_to() { # dest_dir
  local dest="$1" ram="$GFL_RUN_DIR/ram" rel src dst n=0 skip=0 ren=0 h
  mkdir -p "$dest" || return 1
  while IFS= read -r rel; do
    src="$ram/$rel"; dst="$dest/$rel"
    mkdir -p "$(dirname "$dst")" || return 1
    if [ "$rel" = gopforge-live.log ]; then        # the session log is appended, then emptied in RAM
      [ -s "$src" ] || continue
      { printf '\n----- appended from a memory-only session (%s) -----\n' "$(date '+%Y-%m-%d %H:%M')"; cat "$src"; } >>"$dst" || return 1
      : >"$src"; continue
    fi
    if [ -f "$dst" ]; then
      if cmp -s "$src" "$dst"; then skip=$((skip+1)); h="$(sha256_of "$src")"; echo "$h $rel" >>"$GFL_RUN_DIR/saved.list"; continue; fi
      local base="${dst%.*}" ext="" i=2; [ "$base" != "$dst" ] && ext=".${dst##*.}"
      while [ -e "$base-$i$ext" ]; do i=$((i+1)); done
      dst="$base-$i$ext"; ren=$((ren+1))
    fi
    cp -p "$src" "$dst" 2>/dev/null || cp "$src" "$dst" || return 1
    n=$((n+1))
  done < <(cd "$ram" && find . -type f -printf '%P\n' | sort)
  sync 2>/dev/null || true
  # Re-read from the drive rather than the page cache before trusting the copies.
  [ "$(id -u)" = 0 ] && [ "${GFL_MOCK:-0}" != 1 ] && echo 1 >/proc/sys/vm/drop_caches 2>/dev/null
  while IFS= read -r rel; do
    [ "$rel" = gopforge-live.log ] && continue
    h="$(sha256_of "$ram/$rel")"
    grep -qxF "$h $rel" "$GFL_RUN_DIR/saved.list" 2>/dev/null && continue
    # find the copy (it may have been renamed -N)
    local found="" c
    for c in "$dest/$rel" "${dest}/${rel%.*}"-*."${rel##*.}"; do
      [ -f "$c" ] && [ "$(sha256_of "$c")" = "$h" ] && { found="$c"; break; }
    done
    [ -n "$found" ] || { echo "verify failed: $rel" >&2; return 3; }
    echo "$h $rel" >>"$GFL_RUN_DIR/saved.list"
  done < <(cd "$ram" && find . -type f -printf '%P\n' | sort)
  ln -sfn "$dest" "$GFL_RUN_DIR/work.new" && mv -Tf "$GFL_RUN_DIR/work.new" "$GFL_RUN_DIR/work" || return 1
  echo "$n $skip $ren"
}

# Stop using the drive: point the workdir back at RAM, flush, unmount what we mounted.
gfl_save_eject() {
  local mp=""
  [ -f "$GFL_RUN_DIR/drive.json" ] && mp="$(jq -r '.mountpoint // empty' "$GFL_RUN_DIR/drive.json" 2>/dev/null)"
  ln -sfn "$GFL_RUN_DIR/ram" "$GFL_RUN_DIR/work.new" && mv -Tf "$GFL_RUN_DIR/work.new" "$GFL_RUN_DIR/work"
  rm -f "$GFL_RUN_DIR/drive.json"
  sync 2>/dev/null || true
  [ "${GFL_MOCK:-0}" = 1 ] && return 0
  case "$mp" in "$GFL_SAVE_MNT_ROOT"/*) umount "$mp" 2>/dev/null || umount -l "$mp" 2>/dev/null; rmdir "$mp" 2>/dev/null ;; esac
  return 0
}
