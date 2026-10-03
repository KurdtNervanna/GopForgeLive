#!/usr/bin/env python3
"""Print the README's compatibility tables from catalog/imac-boot-screen-matrix.json,
so the README always matches what the app recommends.   py dev/compat-table.py"""
import json
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
M = json.loads((REPO / "catalog" / "imac-boot-screen-matrix.json").read_text(encoding="utf-8"))
ORDER = ["gop", "eg2", "eg", "eg91", "uga"]
LABEL = {"gop": "GOP", "eg2": "EG2", "eg": "EG", "eg91": "EG91", "uga": "UGA"}


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


out = []
out.append("| Card | Chip | PCI ID | Firmware types | LVDS iMacs | Notes |")
out.append("|---|---|---|---|---|---|")
for c in M["cards"]:
    methods = {r["method"] for r in c["roms"]}
    fw = ", ".join(LABEL[m] for m in ORDER if m in methods)
    ids = ", ".join(f"`1002:{d}`" for d in c["match"].get("device", []))
    out.append(f"| {c['name'].split(' (')[0]} | {c.get('family', '')} | {ids} | {fw} | {lvds(c)} | {short(c.get('notes'))} |")

out.append("")
out.append("| iMac | Panel | Notes |")
out.append("|---|---|---|")
for key, r in M["model_rules"].items():
    if r.get("ambiguous"):
        continue                      # the app asks A1311 vs A1312 itself
    panel = {"lvds": "LVDS", "edp": "eDP"}.get(r.get("panel"), r.get("panel", ""))
    out.append(f"| {key} | {panel} | {short(r.get('note'), 170)} |")

print("\n".join(out))
