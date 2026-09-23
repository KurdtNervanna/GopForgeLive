#!/usr/bin/env bash
# fetch-roms.sh — pull the whole IMAC-EFI-BOOT-SCREEN vBIOS library into roms/.
#
# Downloads Ausdauersportler/IMAC-EFI-BOOT-SCREEN (GPL-3.0), unzips the packed
# ROMs, and lays them out under roms/<METHOD>/ so install-to-usb.sh bakes the
# full library onto the boot disk. Also generates roms/index.json by reading the
# PCI device id straight out of each vBIOS (no guessing).
#
# Run on a networked machine before building the USB. These blobs are GPL-3.0
# and stay vendored (not committed to this MIT repo) — the upstream LICENSE is
# copied to roms/UPSTREAM-LICENSE.
set -Eeuo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="$HERE/vendor/imac-efi-boot-screen"
ROMS="$HERE/roms"
REPO="${IMAC_ROMS_REPO:-https://github.com/Ausdauersportler/IMAC-EFI-BOOT-SCREEN.git}"
REF="${IMAC_ROMS_REF:-main}"

# Which upstream folders hold flashable/reference ROMs.
METHODS=(GOP EG EG2 UGA LVDS ORIG Apple)

say() { printf '» %s\n' "$*"; }

# 1. get the source
if [ -d "$VENDOR/.git" ]; then
  say "updating IMAC-EFI-BOOT-SCREEN …"
  git -C "$VENDOR" fetch --depth 1 origin "$REF" && git -C "$VENDOR" checkout -q FETCH_HEAD
else
  say "cloning IMAC-EFI-BOOT-SCREEN ($REF) …"
  git clone --depth 1 --branch "$REF" "$REPO" "$VENDOR"
fi

# 2. copy + unzip into roms/<METHOD>/
mkdir -p "$ROMS"
cp -f "$VENDOR/LICENSE" "$ROMS/UPSTREAM-LICENSE" 2>/dev/null || true
cat > "$ROMS/UPSTREAM-NOTICE.txt" <<EOF
vBIOS ROMs in this folder come from:
  https://github.com/Ausdauersportler/IMAC-EFI-BOOT-SCREEN  (GPL-3.0)
They are redistributed under the GPL-3.0 (see UPSTREAM-LICENSE), separate from
GopForge-Live's own MIT license. Fetched $(date -u +%Y-%m-%dT%H:%MZ) at ref $REF.
Folders: GOP (native GOP), EG (EnableGop), EG2 (EnableGop2), UGA (legacy),
LVDS (LVDS-panel GOP), ORIG (untouched dumps), Apple (original Apple cards).
EOF

for m in "${METHODS[@]}"; do
  [ -d "$VENDOR/$m" ] || continue
  mkdir -p "$ROMS/$m"
  # loose .rom
  find "$VENDOR/$m" -maxdepth 1 -type f -iname '*.rom' -exec cp -f {} "$ROMS/$m/" \;
  # zipped .rom.zip -> extract the .rom inside
  local_zip=0
  while IFS= read -r z; do
    [ -n "$z" ] || continue
    unzip -o -j -q "$z" -d "$ROMS/$m/" '*.rom' 2>/dev/null || unzip -o -j -q "$z" -d "$ROMS/$m/" 2>/dev/null || true
    local_zip=$((local_zip+1))
  done < <(find "$VENDOR/$m" -maxdepth 1 -type f -iname '*.rom.zip')
  say "$m: $(find "$ROMS/$m" -type f -iname '*.rom' | wc -l | tr -d ' ') roms"
done

# 3. build index.json (device id read from each ROM's PCIR)
say "indexing device ids from ROM binaries …"
if command -v python3 >/dev/null 2>&1; then
  python3 - "$ROMS" > "$ROMS/index.json" <<'PY'
import sys, os, json, hashlib
root = sys.argv[1]
def pcir_ids(data):
    # scan every PCIR structure; return list of (vendor,device) hex
    out=[]; i=0
    while True:
        i=data.find(b'PCIR', i)
        if i<0: break
        if i+8<=len(data):
            ven=int.from_bytes(data[i+4:i+6],'little')
            dev=int.from_bytes(data[i+6:i+8],'little')
            out.append(("%04x"%ven, "%04x"%dev))
        i+=4
    return out
entries=[]
for dirpath,_,files in os.walk(root):
    for f in files:
        if not f.lower().endswith('.rom'): continue
        p=os.path.join(dirpath,f)
        try: data=open(p,'rb').read()
        except OSError: continue
        rel=os.path.relpath(p,root).replace('\\','/')
        ids=pcir_ids(data)
        gpu=[(v,d) for (v,d) in ids if v in ('1002','10de')]
        entries.append({
          "file": rel,
          "method": rel.split('/')[0],
          "size": len(data),
          "sha256": hashlib.sha256(data).hexdigest(),
          "vendor": (gpu[0][0] if gpu else (ids[0][0] if ids else "")),
          "device": (gpu[0][1] if gpu else (ids[0][1] if ids else "")),
          "all_ids": ["%s:%s"%(v,d) for (v,d) in ids],
        })
entries.sort(key=lambda e:e["file"])
json.dump({"generated":"pcir-scan","count":len(entries),"roms":entries}, sys.stdout, indent=2)
PY
  say "index.json: $(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["count"])' "$ROMS/index.json") roms"
else
  say "python3 not found — skipping index.json (name-based matching still works)"
fi

echo "✓ ROM library ready under $ROMS/"
