// macs.js — friendly names for Macs, GPUs and firmware methods.

const MACS = {
  "MacPro1,1": { name: "Mac Pro", when: "2006" },
  "MacPro2,1": { name: "Mac Pro", when: "2007" },
  "MacPro3,1": { name: "Mac Pro", when: "Early 2008" },
  "MacPro4,1": { name: "Mac Pro", when: "Early 2009" },
  "MacPro5,1": { name: "Mac Pro", when: "Mid 2010 – Mid 2012" },
  "iMac9,1":   { name: "iMac", when: "Early 2009 · 20/24-inch" },
  "iMac10,1":  { name: "iMac", when: "Late 2009 · 21.5/27-inch" },
  "iMac11,1":  { name: "iMac", when: "Late 2009 · 27-inch" },
  "iMac11,2":  { name: "iMac", when: "Mid 2010 · 21.5-inch" },
  "iMac11,3":  { name: "iMac", when: "Mid 2010 · 27-inch" },
  "iMac12,1":  { name: "iMac", when: "Mid 2011 · 21.5-inch" },
  "iMac12,2":  { name: "iMac", when: "Mid 2011 · 27-inch" },
};

export function macInfo(model) {
  if (!model) return { name: "This Computer", when: "Not an Apple Mac", model: "" };
  const m = MACS[model];
  if (m) return { ...m, model };
  const fam = /^iMac/.test(model) ? "iMac" : /^MacPro/.test(model) ? "Mac Pro" : /^Macmini/.test(model) ? "Mac mini" : /^MacBook/.test(model) ? "MacBook" : "Mac";
  return { name: fam, when: "", model };
}

export const CLASS = {
  "cmp-bootrom": { pill: "Boot ROM ready", tone: "green", path: "Boot ROM with EnableGop" },
  "imac-gpu":    { pill: "Graphics firmware", tone: "blue", path: "GOP graphics firmware" },
  "unsupported": { pill: "Not supported", tone: "orange", path: "None" },
};

/** "VGA … [AMD/ATI] Ellesmere [Radeon RX 470/…] [1002:67df] (rev e7)" → "Radeon RX 470/…" */
export function gpuName(raw = "") {
  let s = String(raw).replace(/^[^:]*:\s*/, "")
    .replace(/\s*\[[0-9a-f]{4}:[0-9a-f]{4}\]/i, "").replace(/\s*\(rev [0-9a-f]+\)/i, "").trim();
  const m = s.match(/\[([^\]]*(Radeon|GeForce|FirePro|Quadro|Pro|Vega|RX)[^\]]*)\]\s*$/i);
  if (m) return m[1];
  return s.replace(/Advanced Micro Devices, Inc\. \[AMD\/ATI\]\s*/i, "AMD ")
          .replace(/NVIDIA Corporation\s*/i, "NVIDIA ") || "Display controller";
}
export function gpuChip(raw = "") {
  const s = String(raw).replace(/^[^:]*:\s*/, "");
  const m = s.match(/\]\s*([^[]+?)\s*\[/);
  return m ? m[1].trim() : "";
}

export const METHODS = {
  gop:  { label: "GOP",  name: "Native GOP",     blurb: "UEFI Graphics Output Protocol built into the card's firmware. The preferred method." },
  eg2:  { label: "EG2",  name: "EnableGop 2",    blurb: "Newer EnableGop build. Don't use on the 27-inch iMac10,1 (white screen)." },
  eg:   { label: "EG",   name: "EnableGop",      blurb: "EnableGop driver in the vBIOS. Works on every supported iMac." },
  eg91: { label: "EG91", name: "EnableGop 9,1",  blurb: "Special EnableGop build required by the iMac9,1 (LVDS panel)." },
  uga:  { label: "UGA",  name: "UGA",            blurb: "Legacy boot-screen method for older EFI." },
  orig: { label: "ORIG", name: "Original",       blurb: "Untouched vendor dump — reference only." },
  lvds: { label: "LVDS", name: "LVDS",           blurb: "GOP build for LVDS panels." },
  apple:{ label: "APPLE", name: "Apple",         blurb: "Original Apple card firmware." },
};
export const method = (m) => METHODS[m] || { label: String(m || "?").toUpperCase(), name: m, blurb: "" };

/** "EG2/WX4150-EG2_adj_ALT_VRAM.rom" → "WX4150 EG2 adj ALT VRAM" */
export function romTitle(file = "") {
  return String(file).split("/").pop().replace(/\.rom$/i, "").replace(/[_-]+/g, " ").replace(/\s+/g, " ").trim();
}

export function romTags(r) {
  const t = [];
  if (r.mem) t.push(`Memory · ${r.mem}`);
  if (r.vram) t.push(r.vram === "alt" ? "Alternate VRAM straps" : `VRAM · ${r.vram}`);
  if (r.panel === "lvds") t.push("LVDS panel");
  if (r.note) t.push(r.note);
  return t;
}
