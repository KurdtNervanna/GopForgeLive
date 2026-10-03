#!/usr/bin/env python3
"""The README's compatibility tables, generated from catalog/imac-boot-screen-matrix.json
so the README always matches what the app recommends.

    py dev/compat-table.py           print the tables
    py dev/compat-table.py --write   replace them in README.md (between the compat markers)
"""
import json, sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
M = json.loads((REPO / "catalog" / "imac-boot-screen-matrix.json").read_text(encoding="utf-8"))
ORDER = ["gop", "eg2", "eg", "eg91", "uga"]
LABEL = {"gop": "GOP", "eg2": "EG2", "eg": "EG", "eg91": "EG91", "uga": "UGA"}
START, END = "<!-- compat:start -->", "<!-- compat:end -->"


def lvds(card):
    if card.get("lvds") is True:
        return "✓"
    if card.get("lvds") is False:
        return "✗ (eDP only)"
    return "—"


def short(note, n=150):
    note = " ".join((note or "").split())
    for a, b in (("MATCH THE MEMORY VENDOR", "Match the memory vendor"), ("Runs HOT", "Runs hot"),
                 ("(README note 4)", "(upstream README, note 4)"), (" (README)", "")):
        note = note.replace(a, b)
    return note if len(note) <= n else note[: n - 1].rsplit(" ", 1)[0] + "…"


def tables() -> str:
    out = ["| Card | Chip | PCI ID | Firmware types | LVDS iMacs | 27″ backlight add-on | Notes |",
           "|---|---|---|---|---|---|---|"]
    for c in M["cards"]:
        methods = {r["method"] for r in c["roms"]}
        fw = ", ".join(LABEL[m] for m in ORDER if m in methods)
        ids = ", ".join(f"`1002:{d}`" for d in c["match"].get("device", []))
        addon = "**Needed**" if c.get("backlight_addon") else "—"
        out.append(f"| {c['name'].split(' (')[0]} | {c.get('family', '')} | {ids} | {fw} | {lvds(c)} | {addon} | {short(c.get('notes'))} |")
    out += ["", "| iMac | Screen | Panel | Notes |", "|---|---|---|---|"]
    for key, r in M["model_rules"].items():
        if r.get("ambiguous"):
            continue                      # the app asks A1311 vs A1312 itself
        panel = {"lvds": "LVDS", "edp": "eDP"}.get(r.get("panel"), r.get("panel", ""))
        inch = f"{r['inch']:g}″" if r.get("inch") else ""
        out.append(f"| {key} | {inch} | {panel} | {short(r.get('note'), 170)} |")
    return "\n".join(out)


if __name__ == "__main__":
    t = tables()
    if "--write" in sys.argv:
        readme = REPO / "README.md"
        s = readme.read_text(encoding="utf-8")
        a, b = s.index(START) + len(START), s.index(END)
        readme.write_text(s[:a] + "\n" + t + "\n" + s[b:], encoding="utf-8", newline="\n")
        print("README.md tables updated")
    else:
        sys.stdout.reconfigure(encoding="utf-8")
        print(t)
