// Overview — this Mac at a glance and what the disk can do for it.
import { html, when } from "../dom.js";
import { icon, status, sq } from "../icons.js";
import { macArt } from "../art.js";
import { S, actions, update } from "../core.js";
import { api } from "../api.js";
import { section, callout, kv, navRow } from "../components.js";
import { macInfo, CLASS, gpuName } from "../macs.js";

export const title = "Overview";

export async function enter() {
  if (!S.gpus) {
    const g = await api.get("/api/gpus");
    if (g.ok) update({ gpus: g.gpus });
  }
}

function toolRows(st) {
  const t = st.tools;
  const inj = {
    ok: ["ok", "Ready", "DXEInject for Linux (UEFITool engine)"],
    mock: ["ok", "Simulated", "Demo mode"],
    broken: ["bad", "Won’t start", "The Linux injector failed to load — see Activity"],
    "macos-only": ["warn", "macOS-only build", "Patching the Boot ROM needs a Linux injector — reading and backups still work"],
    missing: ["bad", "Missing", "Run tools/fetch-vendor.sh before building the USB"],
    unknown: ["warn", "Unrecognised", "Couldn't identify the injector binary"],
  }[t.injector] || ["warn", t.injector, ""];
  const ffs = t.enablegop_ffs || {};
  const rows = [
    ["chip", "orange", "Boot ROM reader / writer", "flashrom", t.flashrom ? ["ok", "Available"] : ["bad", "Missing"]],
    ["gpu", "red", "AMD graphics firmware tool", "amdvbflash", t.amdvbflash ? ["ok", "Available"] : ["warn", "Not found"]],
    ["gpu", "green", "NVIDIA graphics firmware tool", "nvflash", t.nvflash ? ["ok", "Available"] : ["warn", "Not found"]],
    ["wrench", "indigo", "GopForge", "Boot ROM inspector & patcher", t.gopforge ? ["ok", "Available"] : ["bad", "Missing"]],
    ["layers", "blue", "EnableGop drivers", ffs.standard || ffs.direct ? `${[ffs.standard && "Standard", ffs.direct && "Direct"].filter(Boolean).join(" + ")} cached` : "not cached",
      ffs.standard && ffs.direct ? ["ok", "Ready"] : ffs.standard || ffs.direct ? ["warn", "Partial"] : ["warn", "Not cached"]],
    ["bolt", "purple", "EnableGop injector", inj[2], [inj[0], inj[1]]],
    ["archive", "teal", "Graphics ROM library", `${st.library.roms} firmware images`, st.library.roms ? ["ok", "Loaded"] : ["warn", "Empty"]],
  ];
  return html`<div class="group icons">${rows.map(([ic, col, t1, t2, [lvl, val]]) => html`
    <div class="row">${sq(ic, col)}
      <div class="main-col"><div class="title">${t1}</div><div class="subtitle">${t2}</div></div>
      <div class="value nowrap">${val}</div>${status(lvl)}
    </div>`)}</div>`;
}

export function render() {
  const st = S.status;
  const m = st.machine;
  const info = macInfo(m.model);
  const cls = CLASS[m.class] || CLASS.unsupported;
  const expert = S.status.expert;
  const gpu0 = S.gpus && S.gpus[0];

  const cta = [];
  if (m.allow_bootrom || expert)
    cta.push(navRow("bootrom", "chip", "orange", "Add a native boot screen",
      "Back up, patch and flash your Mac Pro’s Boot ROM with EnableGop"));
  if (m.allow_gpu || expert)
    cta.push(navRow("gpu", "gpu", "purple", "Install boot-screen graphics firmware",
      "Pick the right GOP-enabled vBIOS for your graphics card and flash it safely"));

  return html`
  <div class="page">
    <div class="hero">
      <div class="art">${macArt(m.model)}</div>
      <div class="who">
        <div class="eyebrow">This Mac</div>
        <h1 class="t-title1 name">${info.name}</h1>
        <div class="meta">${[info.when, m.model || "Unknown model"].filter(Boolean).join(" · ")}</div>
        <div class="chips">
          <span class="pill ${cls.tone}">${icon(m.class === "unsupported" ? "alert" : "shieldCheck")} ${cls.pill}</span>
          ${when(expert, () => html`<span class="pill orange">${icon("wrench")} Expert Mode</span>`)}
          ${when(st.mock, () => html`<span class="pill purple">${icon("sparkle")} Demo — simulated hardware</span>`)}
        </div>
      </div>
    </div>

    ${when(cta.length, () => section("Get Started", html`<div class="group">${cta}</div>`,
      m.model === "MacPro5,1" ? "A Mac Pro 4,1 upgraded with 5,1 firmware also identifies as MacPro5,1 — both are supported." : ""))}

    ${when(!cta.length, () => html`<div class="section">${callout("warn", "Nothing to do on this computer",
      html`${m.note} If you know exactly what you’re doing, <a href="#" data-act="sheet" data-sheet="expert" style="color:var(--blue)">Expert Mode</a> unlocks every tool without the safety gating.`)}</div>`)}

    ${section("About This Mac", html`
      <div class="group info-grid">
        ${kv("Model Identifier", m.model || "—")}
        ${kv("Boot-screen method", cls.path)}
        ${kv("Graphics", gpu0 ? gpuName(gpu0.name) : S.gpus ? "None detected" : "Detecting…")}
        ${kv("Graphics IDs", gpu0 ? `${gpu0.vendor}:${gpu0.device} · ${gpu0.subsys}` : "—")}
        ${kv("Backups & log saved to", st.storage.on_usb ? "This USB drive" : "Memory only — lost at shut-down")}
        ${kv("GopForge Live", st.version)}
      </div>`, when(!st.storage.on_usb, () => "The USB’s data partition wasn’t found writable, so backups can’t be kept. Don’t flash anything until this is resolved."))}

    ${section("Tools on This Disk", toolRows(st))}

    <div class="btn-row start" style="margin-top:var(--s5)">
      <button class="btn" data-act="sheet" data-sheet="hardware">${icon("info")} Full Hardware Report</button>
    </div>
  </div>`;
}

Object.assign(actions, {});
