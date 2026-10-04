#!/usr/bin/env python3
"""bootrom_rebuild.py — rebuild a Mac Pro 4,1/5,1 Boot ROM on a 144.0.0.0.0 template.

Implements Borowski's "rebuild/update Mac Pro 4.1/5.1 bootrom with template files"
procedure (MacRumors, 2024) as code, so a 4,1 can be crossflashed to 5,1 firmware and a
5,1 can be refreshed to a clean 144.0.0.0.0 image:

  1. the donor's individual Fsys entries (ssn, hwc, son, …) replace the template's
     Fsys EOF marker; the donor's Gaid entries replace the template's Gaid EOF marker;
  2. both store CRC32s are recomputed;
  3. the donor's 0x80-byte identity block at 0x3FFF00 (MAC address, LBSN, build date)
     goes into the template's volume-top file; that file's checksum and the last
     volume's AppleCRC32 / header checksum are recomputed.

Everything else comes from the template, so NVRAM ends up empty (no stale VSS data,
no firmware password, startup disk must be chosen again).

    bootrom_rebuild.py identity <rom>                 JSON facts about an image
    bootrom_rebuild.py rebuild <template> <donor> <out>

Exit: 0 ok · 2 file error · 3 template not recognised · 4 donor unusable · 5 self-check failed
SPDX-License-Identifier: MIT
"""
import json, re, struct, sys, zlib

SIZE = 4 * 1024 * 1024
NVRAM = (0x120000, 0x150000)            # EFISystemNvDataFv on MP4,1/5,1
ID_BLOCK = (0x3FFF00, 0x80)             # MAC address + checksum, LBSN, build date
LAST_VOL = 0x3F0000                     # volume holding the volume-top file
FFS_ATTRIB_CHECKSUM = 0x40
BIOS_ID = re.compile(rb"(?:M\x00P\x00[0-9]\x00[0-9]\x00\.\x008\x008\x00Z\x00(?:\.\x00[0-9A-Z]\x00(?:[0-9A-Z]\x00)*){3})")
# Fsys entries the template already provides; a donor may carry its own copies before 'ssn'.
TEMPLATE_OWNED = {"overrides", "override-version"}


class Fail(Exception):
    def __init__(self, code, msg):
        super().__init__(msg)
        self.code = code


# --- Apple Fsys / Gaid stores -----------------------------------------------------
def find_store(d, sig):
    """(offset, size) of the Fsys/Gaid store inside the NVRAM region, or None."""
    i = d.find(sig, *NVRAM)
    if i < 0:
        return None
    size = struct.unpack_from("<H", d, i + 9)[0]
    if not 0x20 <= size <= NVRAM[1] - i:
        return None
    return i, size


def store_crc_ok(d, store):
    off, size = store
    return struct.unpack_from("<I", d, off + size - 4)[0] == zlib.crc32(d[off:off + size - 4]) & 0xFFFFFFFF


def set_store_crc(b, store):
    off, size = store
    struct.pack_into("<I", b, off + size - 4, zlib.crc32(bytes(b[off:off + size - 4])) & 0xFFFFFFFF)


def parse_entries(d, store):
    """[(name, entry_offset, entry_bytes)] up to (excluding) EOF; plus the EOF offset.
    Entry = name length (1) · name · value length (2, LE) · value. EOF = 03 'EOF'."""
    off, size = store
    p, end, out = off + 11, off + size - 4, []
    while p < end:
        n = d[p]
        name = d[p + 1:p + 1 + n]
        if name == b"EOF":
            return out, p
        if n == 0 or p + 1 + n + 2 > end:
            break
        vlen = struct.unpack_from("<H", d, p + 1 + n)[0]
        q = p + 1 + n + 2 + vlen
        if q > end:
            break
        out.append((name.decode("latin-1"), p, bytes(d[p:q])))
        p = q
    raise Fail(4, f"store at 0x{off:X} is damaged (no EOF marker)")


def entry_value(raw):
    n = raw[0]
    return raw[1 + n + 2:]


def printable(v):
    v = v.rstrip(b"\0")
    return v.decode("ascii") if v and all(32 <= c < 127 for c in v) else v.hex()


# --- identity --------------------------------------------------------------------
def bios_id(d):
    m = BIOS_ID.search(d)
    return m.group(0).decode("utf-16-le") if m else ""


def identity(d):
    facts = {"size": len(d), "bios_id": bios_id(d)}
    facts["model"] = facts["bios_id"][:4] if facts["bios_id"] else ""
    for sig in (b"Fsys", b"Gaid"):
        st = find_store(d, sig)
        key = sig.decode().lower()
        if not st:
            facts[key] = None
            continue
        ents, eof = parse_entries(d, st)
        facts[key] = {"offset": st[0], "size": st[1], "crc_ok": store_crc_ok(d, st), "eof": eof,
                      "entries": [n for n, _, _ in ents]}
        if sig == b"Fsys":
            vals = {n: entry_value(raw) for n, _, raw in ents}
            facts["serial"] = printable(vals["ssn"]) if "ssn" in vals else ""
            facts["hwc"] = printable(vals["hwc"]) if "hwc" in vals else ""
    blk = d[ID_BLOCK[0]:ID_BLOCK[0] + ID_BLOCK[1]]
    facts["id_block_present"] = blk not in (b"\xff" * ID_BLOCK[1], bytes(ID_BLOCK[1]))
    m = re.search(rb"[A-Z0-9]{12,17}", blk)
    facts["lbsn"] = m.group(0).decode() if m else ""
    return facts


# --- volume-top file + last volume checksums -------------------------------------
def fix_last_volume(b):
    vs = LAST_VOL
    if b[vs + 40:vs + 44] != b"_FVH":
        raise Fail(3, "template has no firmware volume at 0x3F0000")
    vl = struct.unpack_from("<Q", b, vs + 32)[0]
    hlen = struct.unpack_from("<H", b, vs + 48)[0]
    if vs + vl != SIZE:
        raise Fail(3, "the last volume does not end at the top of the image")
    # the FFS file that holds the identity block
    p, hit = vs + hlen, None
    while p + 24 <= vs + vl:
        fsize = int.from_bytes(b[p + 20:p + 23], "little")
        if fsize < 24 or fsize == 0xFFFFFF:
            break
        if p <= ID_BLOCK[0] and ID_BLOCK[0] + ID_BLOCK[1] <= p + fsize:
            hit = (p, fsize)
            break
        p = (p + fsize + 7) & ~7
    if not hit:
        raise Fail(3, "no file covers the identity block in the last volume")
    fp, fsize = hit
    if b[fp + 19] & FFS_ATTRIB_CHECKSUM:
        b[fp + 17] = (0x100 - (sum(b[fp + 24:fp + fsize]) & 0xFF)) & 0xFF
    # AppleCRC32 in the ZeroVector (CRC32 of the volume body), then the header checksum
    struct.pack_into("<I", b, vs + 8, zlib.crc32(bytes(b[vs + hlen:vs + vl])) & 0xFFFFFFFF)
    struct.pack_into("<H", b, vs + 50, 0)
    s = sum(struct.unpack_from(f"<{hlen // 2}H", b, vs)) & 0xFFFF
    struct.pack_into("<H", b, vs + 50, (0x10000 - s) & 0xFFFF)


def last_volume_ok(d):
    vs = LAST_VOL
    vl = struct.unpack_from("<Q", d, vs + 32)[0]
    hlen = struct.unpack_from("<H", d, vs + 48)[0]
    crc_ok = struct.unpack_from("<I", d, vs + 8)[0] == zlib.crc32(d[vs + hlen:vs + vl]) & 0xFFFFFFFF
    hdr_ok = sum(struct.unpack_from(f"<{hlen // 2}H", d, vs)) & 0xFFFF == 0
    return crc_ok and hdr_ok


# --- rebuild -----------------------------------------------------------------------
def rebuild(tpl, donor):
    if len(tpl) != SIZE or len(donor) != SIZE:
        raise Fail(2, "template and donor must both be 4 MiB images")
    t_fs, t_ga = find_store(tpl, b"Fsys"), find_store(tpl, b"Gaid")
    if not (t_fs and t_ga and store_crc_ok(tpl, t_fs) and store_crc_ok(tpl, t_ga)):
        raise Fail(3, "template has no valid Fsys/Gaid stores")
    t_fs_ents, t_fs_eof = parse_entries(tpl, t_fs)
    t_ga_ents, t_ga_eof = parse_entries(tpl, t_ga)
    if t_ga_ents or tpl[ID_BLOCK[0]:ID_BLOCK[0] + ID_BLOCK[1]] != b"\xff" * ID_BLOCK[1] \
            or "ssn" in [n for n, _, _ in t_fs_ents]:
        raise Fail(3, "template already contains machine data — use an unmodified template")
    if not last_volume_ok(tpl):
        raise Fail(3, "template's last volume checksums are not valid")

    d_fs, d_ga = find_store(donor, b"Fsys"), find_store(donor, b"Gaid")
    if not d_fs:
        raise Fail(4, "the backup has no Fsys store (no serial number data)")
    if not d_ga:
        raise Fail(4, "the backup has no Gaid store")
    d_fs_ents, _ = parse_entries(donor, d_fs)
    d_ga_ents, _ = parse_entries(donor, d_ga)
    names = [n for n, _, _ in d_fs_ents]
    if "ssn" not in names:
        raise Fail(4, "the backup's Fsys store has no serial number (ssn)")
    i = names.index("ssn")
    unknown = [n for n in names[:i] if n not in TEMPLATE_OWNED]
    if unknown:
        raise Fail(4, f"unexpected Fsys entries before ssn: {', '.join(unknown)} — not the layout the procedure expects")
    personal = b"".join(raw for _, _, raw in d_fs_ents[i:])
    gaid = b"".join(raw for _, _, raw in d_ga_ents)
    blk = donor[ID_BLOCK[0]:ID_BLOCK[0] + ID_BLOCK[1]]
    if blk in (b"\xff" * ID_BLOCK[1], bytes(ID_BLOCK[1])):
        raise Fail(4, "the backup's identity block (MAC address, LBSN) at 0x3FFF00 is empty")

    out = bytearray(tpl)
    for (off, size), eof, payload in ((t_fs, t_fs_eof, personal), (t_ga, t_ga_eof, gaid)):
        new = payload + b"\x03EOF"
        if eof + len(new) > off + size - 4:
            raise Fail(4, "the backup's entries do not fit in the template store")
        tail = bytes(out[eof:off + size - 4])
        if tail.strip(b"\0") != b"\x03EOF":
            raise Fail(3, "template store has data after its EOF marker")
        out[eof:eof + len(new)] = new
        set_store_crc(out, (off, size))
    out[ID_BLOCK[0]:ID_BLOCK[0] + ID_BLOCK[1]] = blk
    fix_last_volume(out)

    # self-check: re-read the result as if it were a fresh dump
    out = bytes(out)
    t_id, d_id, o_id = identity(tpl), identity(donor), identity(out)
    o_fs, o_ga = find_store(out, b"Fsys"), find_store(out, b"Gaid")
    raws = lambda ents: [r for _, _, r in ents]
    stores = (min(t_fs[0], t_ga[0]), max(t_fs[0] + t_fs[1], t_ga[0] + t_ga[1]))
    checks = {
        "fsys_crc": store_crc_ok(out, o_fs), "gaid_crc": store_crc_ok(out, o_ga),
        "last_volume": last_volume_ok(out),
        "serial": bool(d_id["serial"]) and o_id["serial"] == d_id["serial"],
        "hwc": o_id["hwc"] == d_id["hwc"],
        "fsys_entries": raws(parse_entries(out, o_fs)[0]) == raws(t_fs_ents) + raws(d_fs_ents[i:]),
        "gaid_entries": raws(parse_entries(out, o_ga)[0]) == raws(d_ga_ents),
        "id_block": out[ID_BLOCK[0]:ID_BLOCK[0] + ID_BLOCK[1]] == blk,
        # nothing changed outside the two stores and the last volume
        "rest_is_template": out[:stores[0]] == tpl[:stores[0]] and out[stores[1]:LAST_VOL] == tpl[stores[1]:LAST_VOL],
        "bios_id": o_id["bios_id"] == t_id["bios_id"] and o_id["bios_id"].startswith("MP51.88Z"),
    }
    if not all(checks.values()):
        raise Fail(5, "self-check failed: " + ", ".join(k for k, v in checks.items() if not v))
    return out, {"donor": d_id, "template": t_id, "result": o_id, "checks": checks,
                 "crossflash": d_id["model"] == "MP41",
                 "fsys_entries_moved": names[i:], "gaid_entries_moved": [n for n, _, _ in d_ga_ents]}


def main(argv):
    try:
        if len(argv) == 3 and argv[1] == "identity":
            print(json.dumps({"ok": True, **identity(open(argv[2], "rb").read())}))
            return 0
        if len(argv) == 5 and argv[1] == "rebuild":
            tpl, donor = open(argv[2], "rb").read(), open(argv[3], "rb").read()
            out, report = rebuild(tpl, donor)
            with open(argv[4], "wb") as f:
                f.write(out)
            print(json.dumps({"ok": True, **report}))
            return 0
        print(__doc__, file=sys.stderr)
        return 64
    except OSError as e:
        print(json.dumps({"ok": False, "code": 2, "error": str(e)}))
        return 2
    except Fail as e:
        print(json.dumps({"ok": False, "code": e.code, "error": str(e)}))
        return e.code


if __name__ == "__main__":
    sys.exit(main(sys.argv))
