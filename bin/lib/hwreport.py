#!/usr/bin/env python3
"""hwreport.py — everything GopForge Live can learn about this computer.

    hwreport.py summary     JSON: system, Boot ROM, CPUs, memory modules, graphics,
                            Wi-Fi, Bluetooth, Ethernet, storage, audio, USB
    hwreport.py report      the full text report: summary + raw output of each tool
    hwreport.py save <file> write the full report to <file>; print the summary as JSON

Read-only: it only runs query tools (dmidecode, lspci, lsusb, lscpu, lsblk, ip, iw,
sensors, smartctl, inxi, lshw …), each with a time limit; missing tools are skipped.
SPDX-License-Identifier: MIT
"""
import json, os, re, shutil, subprocess, sys, time

TOOL_TIMEOUT = 25


def run(cmd, timeout=TOOL_TIMEOUT):
    """stdout of a command, or '' when the tool is missing, fails to start or times out."""
    if not shutil.which(cmd[0]):
        return ""
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, errors="replace")
        return p.stdout
    except (OSError, subprocess.SubprocessError):
        return ""


# --- dmidecode ------------------------------------------------------------------
def dmi(type_):
    """[{key: value}] for each DMI structure of <type_>."""
    out, cur = [], None
    for line in run(["dmidecode", "-t", str(type_)]).splitlines():
        if line.startswith("Handle "):
            cur = {}
            out.append(cur)
        elif cur is not None and line.startswith("\t") and not line.startswith("\t\t") and ":" in line:
            k, v = line.strip().split(":", 1)
            cur[k.strip()] = v.strip()
    return [b for b in out if b]


def mib(s):
    """'16384 MB' / '16 GB' → MiB (int) or 0."""
    m = re.match(r"(\d+)\s*(MB|GB|TB|kB)", s or "")
    if not m:
        return 0
    n, u = int(m.group(1)), m.group(2)
    return n * {"kB": 1 / 1024, "MB": 1, "GB": 1024, "TB": 1024 * 1024}[u]


def human_mib(n):
    return f"{n / 1024:g} GB" if n >= 1024 else f"{n:g} MB"


# --- PCI / USB ------------------------------------------------------------------
PCI_CLASSES = {
    "0300": "graphics", "0302": "graphics", "0380": "graphics",
    "0280": "wifi", "0200": "ethernet", "0403": "audio", "0401": "audio",
    "0c03": "usb", "0c00": "firewire", "0106": "storage", "0104": "storage", "0108": "storage", "0107": "storage",
    "0c80": "thunderbolt", "0880": "other",
}


def pci_devices():
    devs, cur = [], None
    for line in run(["lspci", "-Dnnk"]).splitlines():
        m = re.match(r"^(\S+)\s+(.+?)\s\[([0-9a-f]{4})\]:\s+(.+)$", line)
        if m:
            name = re.sub(r"\s*\(rev [0-9a-f]+\)\s*$", "", m.group(4))
            name = re.sub(r"\s*\[[0-9a-f]{4}:[0-9a-f]{4}\]\s*$", "", name)
            cur = {"slot": m.group(1), "class_name": m.group(2), "class": m.group(3), "name": name, "driver": ""}
            ids = re.findall(r"\[([0-9a-f]{4}):([0-9a-f]{4})\]", m.group(4))
            if ids:
                cur["id"] = f"{ids[-1][0]}:{ids[-1][1]}"
            cur["kind"] = PCI_CLASSES.get(cur["class"], "other")
            devs.append(cur)
        elif cur and "Kernel driver in use:" in line:
            cur["driver"] = line.split(":", 1)[1].strip()
        elif cur and "Subsystem:" in line:
            cur["subsystem"] = line.split(":", 1)[1].strip()
    return devs


def usb_devices():
    out = []
    for line in run(["lsusb"]).splitlines():
        m = re.match(r"Bus (\d+) Device (\d+): ID ([0-9a-f]{4}:[0-9a-f]{4})\s*(.*)", line)
        if m and not re.search(r"root hub", m.group(4), re.I):
            out.append({"bus": m.group(1), "id": m.group(3), "name": m.group(4).strip() or "(unnamed)"})
    return out


# --- summary --------------------------------------------------------------------
def summary():
    s = {"collected": time.strftime("%Y-%m-%d %H:%M:%S")}
    t0, t1, t2 = (dmi(0) or [{}])[0], (dmi(1) or [{}])[0], (dmi(2) or [{}])[0]
    s["system"] = {"manufacturer": t1.get("Manufacturer", ""), "model": t1.get("Product Name", ""),
                   "version": t1.get("Version", ""), "serial": t1.get("Serial Number", ""),
                   "board": t2.get("Product Name", ""), "board_serial": t2.get("Serial Number", "")}
    s["bootrom"] = {"vendor": t0.get("Vendor", ""), "version": t0.get("Version", ""), "date": t0.get("Release Date", "")}

    # CPUs: SMBIOS per socket, lscpu for totals
    cpus = []
    for b in dmi(4):
        if "Populated" not in b.get("Status", "Populated"):
            continue
        cpus.append({"socket": b.get("Socket Designation", ""), "name": " ".join(b.get("Version", "").split()),
                     "cores": b.get("Core Count", ""), "threads": b.get("Thread Count", ""),
                     "max_mhz": b.get("Max Speed", ""), "mhz": b.get("Current Speed", "")})
    lscpu = dict(l.split(":", 1) for l in run(["lscpu"]).splitlines() if ":" in l)
    lscpu = {k.strip(): v.strip() for k, v in lscpu.items()}
    if not cpus and lscpu.get("Model name"):
        n = int(lscpu.get("Socket(s)", "1") or 1)
        cpus = [{"socket": f"CPU {i + 1}", "name": lscpu["Model name"], "cores": lscpu.get("Core(s) per socket", ""),
                 "threads": "", "max_mhz": lscpu.get("CPU max MHz", ""), "mhz": ""} for i in range(n)]
    s["cpus"] = cpus
    s["cpu_totals"] = {"logical": lscpu.get("CPU(s)", ""), "sockets": lscpu.get("Socket(s)", str(len(cpus)) if cpus else ""),
                       "cores_per_socket": lscpu.get("Core(s) per socket", ""), "threads_per_core": lscpu.get("Thread(s) per core", ""),
                       "virtualization": lscpu.get("Virtualization", ""), "l3": lscpu.get("L3 cache", "")}

    # Memory modules
    dimms, slots = [], 0
    for b in dmi(17):
        slots += 1
        size = mib(b.get("Size", ""))
        if not size:
            continue
        dimms.append({"slot": b.get("Locator", ""), "bank": b.get("Bank Locator", ""), "size_mib": size,
                      "size": human_mib(size), "type": b.get("Type", ""),
                      "speed": b.get("Configured Memory Speed") or b.get("Configured Clock Speed") or b.get("Speed", ""),
                      "manufacturer": b.get("Manufacturer", ""), "part": b.get("Part Number", "").strip(),
                      "serial": b.get("Serial Number", "")})
    arr = (dmi(16) or [{}])[0]
    total = sum(d["size_mib"] for d in dimms)
    if not total:
        m = re.search(r"MemTotal:\s+(\d+) kB", open("/proc/meminfo").read() if os.path.exists("/proc/meminfo") else "")
        total = int(m.group(1)) // 1024 if m else 0
    s["memory"] = {"total_mib": total, "total": human_mib(total) if total else "", "modules": dimms,
                   "slots": slots, "slots_used": len(dimms), "max_capacity": arr.get("Maximum Capacity", "")}

    pci, usb = pci_devices(), usb_devices()
    s["pci"] = pci
    s["usb"] = usb
    pick = lambda kind: [{"name": d["name"], "slot": d["slot"], "driver": d["driver"], "id": d.get("id", "")} for d in pci if d["kind"] == kind]
    s["graphics"], s["ethernet"], s["audio"] = pick("graphics"), pick("ethernet"), pick("audio")
    s["wifi"] = pick("wifi") + [{"name": u["name"], "slot": f"USB {u['bus']}", "driver": "", "id": u["id"]}
                                for u in usb if re.search(r"802\.11|wireless lan|wi-?fi|wlan", u["name"], re.I)]
    s["bluetooth"] = [{"name": u["name"], "id": u["id"]} for u in usb if re.search(r"bluetooth", u["name"], re.I)]

    # Network interfaces with MAC addresses
    ifaces = []
    for line in run(["ip", "-br", "link"]).splitlines():
        p = line.split()
        if len(p) >= 3 and p[0] != "lo":
            ifaces.append({"name": p[0], "state": p[1], "mac": p[2]})
    s["interfaces"] = ifaces

    # Storage
    disks = []
    try:
        j = json.loads(run(["lsblk", "-J", "-d", "-o", "NAME,SIZE,MODEL,SERIAL,TRAN,ROTA,TYPE"]) or "{}")
        for d in j.get("blockdevices", []):
            if d.get("type") in ("disk",) and not str(d.get("name", "")).startswith(("loop", "zram", "ram")):
                disks.append({"name": d.get("name"), "size": d.get("size"), "model": (d.get("model") or "").strip(),
                              "serial": d.get("serial") or "", "transport": d.get("tran") or "",
                              "kind": "HDD" if str(d.get("rota")) in ("1", "True", "true") else "SSD"})
    except ValueError:
        pass
    s["storage"] = disks
    return s


# --- full text report --------------------------------------------------------------
def fmt_summary(s):
    L = []
    sy, br = s["system"], s["bootrom"]
    L.append(f"Model          : {sy['model']} ({sy['manufacturer']})" + (f" · board {sy['board']}" if sy["board"] else ""))
    L.append(f"Boot ROM       : {br['version']}" + (f" ({br['date']})" if br["date"] else ""))
    L.append(f"Serial number  : {sy['serial'] or '—'}")
    if s["cpus"]:
        groups = {}
        for c in s["cpus"]:
            groups.setdefault(c["name"], []).append(c)
        for name, cs in groups.items():
            c = cs[0]
            bits = [f"{c['cores']} cores" if c["cores"] else "", f"{c['threads']} threads" if c["threads"] else "",
                    f"max {c['max_mhz']}" if c["max_mhz"] else ""]
            L.append(f"CPU            : {len(cs)} × {name}" + (f" — {', '.join(b for b in bits if b)} each" if any(bits) else ""))
        t = s["cpu_totals"]
        if t["logical"]:
            L.append(f"                 {t['logical']} logical CPUs in total" + (f", L3 {t['l3']}" if t["l3"] else ""))
    else:
        L.append("CPU            : —")
    m = s["memory"]
    L.append(f"Memory         : {m['total'] or '—'}" + (f" in {m['slots_used']} of {m['slots']} slots" if m["slots"] else "")
             + (f" (max {m['max_capacity']})" if m["max_capacity"] else ""))
    for d in m["modules"]:
        L.append(f"                 {d['slot']:<10} {d['size']:>6} {d['type']} {d['speed']}  {d['manufacturer']} {d['part']}".rstrip())
    for label, key in (("Graphics", "graphics"), ("Wi-Fi", "wifi"), ("Bluetooth", "bluetooth"), ("Ethernet", "ethernet"), ("Audio", "audio")):
        items = s[key] or [{"name": "none detected"}]
        for i, d in enumerate(items):
            extra = f"  [{d['id']}]" if d.get("id") else ""
            extra += f"  driver {d['driver']}" if d.get("driver") else ""
            L.append(f"{(label if i == 0 else ''):<15}: {d['name']}{extra}")
    for i, f in enumerate(s["interfaces"]):
        L.append(f"{('Network' if i == 0 else ''):<15}: {f['name']:<10} {f['mac']}  {f['state']}")
    for i, d in enumerate(s["storage"] or [{"name": "none detected", "size": "", "model": "", "transport": "", "kind": ""}]):
        L.append(f"{('Storage' if i == 0 else ''):<15}: {d['name']:<8} {d['size']:>7}  {d['model']}  {d['transport']} {d['kind']}".rstrip())
    L.append(f"USB devices    : {len(s['usb'])}" + (" — " + "; ".join(u["name"] for u in s["usb"][:8]) if s["usb"] else ""))
    return "\n".join(L)


SECTIONS = [
    ("SMBIOS: Boot ROM, system, board, chassis", ["dmidecode", "-t", "bios", "-t", "system", "-t", "baseboard", "-t", "chassis"]),
    ("SMBIOS: processors", ["dmidecode", "-t", "processor"]),
    ("SMBIOS: memory", ["dmidecode", "-t", "memory"]),
    ("lscpu", ["lscpu"]),
    ("Memory in use (free -h)", ["free", "-h"]),
    ("PCI devices (lspci -nnk)", ["lspci", "-nnk"]),
    ("Graphics detail (lspci -vnn, display controllers)", ["lspci", "-vnn", "-d", "::0300"]),
    ("USB devices (lsusb)", ["lsusb"]),
    ("USB tree (lsusb -t)", ["lsusb", "-t"]),
    ("Block devices (lsblk)", ["lsblk", "-o", "NAME,SIZE,TYPE,TRAN,ROTA,MODEL,SERIAL,FSTYPE,LABEL,MOUNTPOINT"]),
    ("NVMe drives", ["nvme", "list"]),
    ("Network links (ip -br link)", ["ip", "-br", "link"]),
    ("Network addresses (ip -br addr)", ["ip", "-br", "addr"]),
    ("Wireless interfaces (iw dev)", ["iw", "dev"]),
    ("Radio switches (rfkill)", ["rfkill", "list"]),
    ("Temperatures and fans (sensors)", ["sensors"]),
    ("EFI boot entries (efibootmgr -v)", ["efibootmgr", "-v"]),
    ("inxi -Fxx", ["inxi", "-Fxx", "-c0"]),
    ("lshw -short", ["lshw", "-short"]),
    ("Kernel", ["uname", "-a"]),
]


def report():
    s = summary()
    out = [f"GopForge Live hardware report — {s['collected']}", "=" * 72, "", fmt_summary(s), ""]
    disks = [d["name"] for d in s["storage"]]
    sections = SECTIONS[:11] + [(f"Drive health: /dev/{n} (smartctl -i -H)", ["smartctl", "-i", "-H", f"/dev/{n}"]) for n in disks] + SECTIONS[11:]
    for title, cmd in sections:
        text = run(cmd, timeout=40 if cmd[0] in ("inxi", "lshw") else TOOL_TIMEOUT).rstrip()
        out += ["", f"==== {title} " + "=" * max(4, 66 - len(title)), text or "(not available)"]
    if os.path.exists("/proc/cmdline"):
        out += ["", "==== Boot command line " + "=" * 49, open("/proc/cmdline").read().strip()]
    return "\n".join(out) + "\n", s


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "summary":
        print(json.dumps(summary()))
    elif len(sys.argv) == 2 and sys.argv[1] == "report":
        sys.stdout.write(report()[0])
    elif len(sys.argv) == 3 and sys.argv[1] == "save":       # write the report, print the summary
        text, s = report()
        os.makedirs(os.path.dirname(os.path.abspath(sys.argv[2])), exist_ok=True)
        with open(sys.argv[2], "w") as f:
            f.write(text)
        print(json.dumps({**s, "text": text, "saved": os.path.abspath(sys.argv[2])}))
    else:
        print(__doc__, file=sys.stderr)
        sys.exit(64)
