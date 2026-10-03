// Graphics firmware flow (iMac): Card → Firmware → Back Up → Flash → Finish.
import { html, raw, when, shortHash } from "../dom.js";
import { icon, sq, status } from "../icons.js";
import { gpuArt, successArt } from "../art.js";
import { api } from "../api.js";
import { S, actions, update, runJob, openSheet, toast, jobRunning } from "../core.js";
import { section, callout, steps, fileCard, jobBlock, locked, methodBadge } from "../components.js";
import { gpuName, gpuChip, method, romTitle, romTags } from "../macs.js";

export const title = "Graphics Card";
const STEPS = [
  { id: "card", label: "Graphics Card" }, { id: "firmware", label: "Firmware" },
  { id: "backup", label: "Back Up" }, { id: "flash", label: "Flash" }, { id: "finish", label: "Finish" },
];
const G = () => S.gpu;
const myJob = (...n) => (S.job && S.job.owner === "gpu" && n.includes(S.job.action) ? S.job : null);
const selectedGpu = () => (S.gpus || []).find((g) => g.index === G().gpuIndex);
const card = () => G().plan?.cards?.[G().cardIdx];

// 27" iMacs: Saturn / Tonga / Pitcairn (and RX 5500 XT) cards can't switch the
// backlight on before macOS loads — the screen stays dark unless the add-on PCB is fitted.
function backlightCallout(c, p, wrap = "section") {
  if (!c || !p || !["yes", "maybe"].includes(c.backlight_addon)) return "";
  const bl = p.backlight_addon || {};
  const link = bl.url ? html` Board and instructions: <span class="mono select-text">${bl.url}</span>` : "";
  const body = c.backlight_addon === "yes"
    ? html`${bl.note}${link}`
    : html`On the 27-inch model this card needs a small add-on board on the backlight cable, or the screen stays dark at boot until macOS starts. 21.5-inch models don’t need it.${link}`;
  const box = callout(c.backlight_addon === "yes" ? "warn" : "info",
    c.backlight_addon === "yes" ? "Needs the backlight add-on in this 27-inch iMac" : "27-inch iMac? Plan for the backlight add-on", body);
  return wrap === "section" ? html`<div class="section">${box}</div>` : html`<div style="margin-top:var(--s4)">${box}</div>`;
}

const VARIANT_LABEL = {
  "iMac10,1-A1311": ["21.5-inch", "Model A1311 · LVDS display"],
  "iMac10,1-A1312": ["27-inch", "Model A1312 · eDP display"],
};

export async function enter() {
  const tasks = [];
  if (!S.gpus) tasks.push(api.get("/api/gpus").then((g) => g.ok && (S.gpus = g.gpus)));
  if (!G().model) tasks.push(api.get("/api/model").then((m) => m.ok && (G().model = m)));
  await Promise.all(tasks);
  if (G().gpuIndex === null && S.gpus?.length === 1 && S.gpus[0].flasher) G().gpuIndex = S.gpus[0].index;
  update();
}

// ------------------------------------------------------------------ actions --
async function loadPlan() {
  const g = G();
  const q = `/api/plan?gpu=${g.gpuIndex}${g.modelKey ? `&model=${encodeURIComponent(g.modelKey)}` : ""}`;
  g.plan = null; update();
  const p = await api.get(q);
  if (!p.ok) { toast("bad", "Couldn’t load firmware options", p.error); return; }
  g.plan = p; g.rom = null;
  // Several cards can share a PCI ID (e.g. 67e8 = WX4130/4150/4170). Prefer the one
  // whose model number appears in the name lspci reported for this GPU.
  g.cardIdx = Math.max(0, bestCardIndex(p.cards, selectedGpu()?.name || ""));
  const rec = recommended(p.cards[g.cardIdx]);
  if (rec) g.rom = rec;
  update();
}

async function loadAdapters() {
  const gpu = selectedGpu();
  G().adapters = null; update();
  const a = await api.get(`/api/adapters?vendor=${gpu.flasher}`);
  G().adapters = a.ok ? a : { ok: false, error: a.error, indices: [], raw: "" };
  if (a.ok && G().adapter === null) G().adapter = a.indices[0] ?? 0;
  update();
}

async function doBackup() {
  const gpu = selectedGpu();
  const job = await runJob("backup-gpu", { vendor: gpu.flasher, index: G().adapter },
    { owner: "gpu", title: "Saving the current firmware…" });
  if (job?.state === "done") {
    G().backup = job.result.backup;
    toast("ok", "Current firmware backed up", `${job.result.backup.name} saved to the USB.`);
    G().step = "flash";
  } else if (job) toast("bad", "Backup failed", job.result?.error || "See the details.");
  update();
}

function askFlash() {
  const g = G(); const gpu = selectedGpu();
  openSheet({
    kind: "confirm", tone: "danger",
    title: "Flash the graphics firmware?",
    body: html`The card’s firmware is replaced with <strong>${romTitle(g.rom.file)}</strong>. If this is the wrong
      firmware the card may show no picture — you can restore your backup from this USB using another card or over SSH.
      <strong>Don’t turn off the Mac</strong> while it runs.`,
    rows: [["Card", gpuName(gpu.name)], ["Adapter", `#${g.adapter}`], ["New firmware", g.rom.file], ["Your backup", g.backup.name]],
    phrase: "FLASH", action: "Flash Firmware",
    onConfirm: async (confirm) => {
      const job = await runJob("flash-gpu",
        { vendor: gpu.flasher, index: g.adapter, rom: g.rom.file, backup: g.backup.path, model: g.modelKey || "" },
        { owner: "gpu", confirm, hud: true, title: "Flashing graphics firmware", sub: "This takes under a minute." });
      if (job?.state === "done") { g.flashed = true; g.step = "finish"; toast("ok", "Graphics firmware updated", "Shut down completely to finish.", 9000); }
      else if (job) { g.error = job.result?.error; toast("bad", "Flashing failed", g.error || "", 12000); }
      update();
    },
  });
}

Object.assign(actions, {
  "gpu-pick": (el) => { if (jobRunning()) return; G().gpuIndex = Number(el.dataset.i); update(); },
  "gpu-variant": (el) => { G().modelKey = el.dataset.k; update(); },
  "gpu-card": (el) => { G().cardIdx = Number(el.dataset.i); G().rom = recommended(card()); update(); },
  "gpu-rom": (el) => {
    const r = card()?.roms.find((x) => x.file === el.dataset.file);
    if (!r || !selectable(r)) return;
    G().rom = r; update();
  },
  "gpu-adapter": (el) => { G().adapter = Number(el.dataset.i); update(); },
  "gpu-next": async () => {
    const g = G();
    if (g.step === "card") { g.step = "firmware"; update(); await loadPlan(); }
    else if (g.step === "firmware") { g.step = "backup"; g.backup = null; update(); await loadAdapters(); }
  },
  "gpu-back": () => {
    const g = G(); if (jobRunning()) return;
    g.step = { firmware: "card", backup: "firmware", flash: "backup" }[g.step] || "card";
    update();
  },
  "gpu-backup": doBackup,
  "gpu-flash": askFlash,
  "gpu-reset": () => {
    if (jobRunning()) return;
    S.gpu = { step: "card", gpuIndex: null, model: G().model, modelKey: null, plan: null, cardIdx: 0, rom: null,
              adapters: null, adapter: null, backup: null, flashed: false, error: null };
    update();
  },
});

// ------------------------------------------------------------------ helpers --
function bestCardIndex(cards, lspciName) {
  const hay = lspciName.replace(/\s+/g, "").toLowerCase();
  return cards.findIndex((c) =>
    (c.name.match(/\b[A-Z]{1,3}\d{3,4}[A-Z]{0,2}\b/g) || []).some((tok) => hay.includes(tok.toLowerCase())));
}
const blocked = (r) => r.forbidden || r.marker.level === "bad";
const selectable = (r) => r.present && (!blocked(r) || S.status.expert);
function recommended(c) {
  return c?.roms.find((r) => r.present && !blocked(r) && r.marker.level === "ok") || null;
}

function romRow(r, rec) {
  const on = G().rom?.file === r.file;
  const can = selectable(r);
  const lvl = !r.present ? "info" : blocked(r) ? "bad" : r.marker.level;
  const trailing = !r.present ? "Not on this USB" : blocked(r) ? r.marker.text : r.marker.level === "ok" ? "Suitable" : r.marker.text;
  const tags = romTags(r);
  return html`
    <div class="row selectable ${on ? "selected" : ""} ${can ? "link" : "disabled"}" ${can ? raw(`tabindex="0" role="radio" aria-checked="${on}" data-act="gpu-rom" data-file="${r.file}"`) : ""}>
      ${methodBadge(r.method)}
      <div class="main-col">
        <div class="title">${romTitle(r.file)} ${when(rec, () => html`<span class="pill blue" style="margin-left:6px">Recommended</span>`)}</div>
        <div class="subtitle">${method(r.method).name}</div>
        ${when(tags.length, () => html`<div class="tags">${tags.map((t) => html`<span class="tag">${t}</span>`)}</div>`)}
      </div>
      <div class="value nowrap t-footnote">${trailing}</div>
      ${on ? html`<span style="color:var(--blue)">${icon("check")}</span>` : status(lvl)}
    </div>`;
}

// ------------------------------------------------------------------- views --
function viewCard() {
  const g = G(); const m = g.model;
  const gpus = S.gpus;
  const needVariant = m?.ambiguous && !g.modelKey;
  const ready = g.gpuIndex !== null && selectedGpu()?.flasher && !(m?.ambiguous && !g.modelKey);
  return html`<div class="panel">
    <div class="panel-head"><div style="width:84px;height:84px;flex:none">${gpuArt()}</div>
      <div class="txt"><h2 class="t-title2">Choose the graphics card</h2>
        <p>These are the display adapters GopForge Live found. Firmware recommendations depend on the exact card and your iMac’s display type.</p></div></div>
    ${when(m?.ambiguous, () => section("Which iMac is this?", html`
      <div class="choices">${m.variants.map((v) => {
        const [t, sub] = VARIANT_LABEL[v.key] || [v.key, ""];
        return html`<button class="choice ${g.modelKey === v.key ? "on" : ""}" data-act="gpu-variant" data-k="${v.key}">
          <span class="radio"></span><span class="c-title">${icon("imac")} ${t}</span>
          <span class="c-body"><strong style="color:var(--label)">${sub}</strong><br>${v.note}</span></button>`;
      })}</div>`, "Your Mac reports only “iMac10,1”, which covers two iMacs that need different firmware."))}
    ${section("Detected graphics", !gpus ? html`<div class="group"><div class="row"><span class="muted">Detecting…</span></div></div>`
      : !gpus.length ? callout("warn", "No graphics card detected", "lspci didn’t report a display controller.")
      : html`<div class="group icons">${gpus.map((x) => {
          const on = g.gpuIndex === x.index; const can = !!x.flasher;
          return html`<div class="row tall selectable ${on ? "selected" : ""} ${can ? "link" : "disabled"}" ${can ? raw(`tabindex="0" role="radio" aria-checked="${on}" data-act="gpu-pick" data-i="${x.index}"`) : ""}>
            ${sq("gpu", x.vendor === "10de" ? "green" : "red", "lg")}
            <div class="main-col"><div class="title">${gpuName(x.name)}</div>
              <div class="subtitle">${x.vendor_label}${gpuChip(x.name) ? ` · ${gpuChip(x.name)}` : ""} · <span class="mono">${x.vendor}:${x.device}</span> · slot ${x.bdf}</div></div>
            ${on ? html`<span style="color:var(--blue)">${icon("check")}</span>` : can ? "" : html`<span class="value t-footnote">No flasher</span>`}
          </div>`;
        })}</div>`)}
    <div class="btn-row">
      <button class="btn primary large" data-act="gpu-next" ${ready && !needVariant ? "" : "disabled"}>Continue ${icon("chevronRight")}</button>
    </div>
  </div>`;
}

function viewFirmware() {
  const g = G(); const p = g.plan;
  if (!p) return html`<div class="panel"><div class="empty" style="padding:40px"><p class="muted">Finding firmware for this card…</p></div></div>`;
  const c = card();
  if (!c) return html`<div class="panel">${callout("warn", "No matching firmware in the library",
    html`The library covers the AMD cards documented by the IMAC-EFI-BOOT-SCREEN project. ${selectedGpu()?.vendor === "10de" ? "NVIDIA cards need card-specific Kepler ROMs — or OpenCore — instead." : ""}`)}
    <div class="btn-row"><button class="btn" data-act="gpu-back">${icon("chevronLeft")} Back</button><span class="grow"></span>
    <button class="btn" data-act="go" data-to="library">${icon("layers")} Browse the Library</button></div></div>`;
  const rec = recommended(c);
  const groups = [
    ["Recommended", c.roms.filter((r) => r === rec)],
    ["Other compatible firmware", c.roms.filter((r) => r !== rec && r.present && !blocked(r) && r.marker.level !== "warn")],
    ["Use with care", c.roms.filter((r) => r.present && !blocked(r) && r.marker.level === "warn")],
    ["Won’t work on this Mac", c.roms.filter((r) => r.present && blocked(r))],
    ["Not on this USB", c.roms.filter((r) => !r.present)],
  ].filter(([, list]) => list.length);
  const noteKind = c.memory_variants || c.hot ? "warn" : "info";
  return html`<div class="panel">
    <div class="panel-head"><div style="width:84px;height:84px;flex:none">${gpuArt()}</div>
      <div class="txt"><h2 class="t-title2">${c.name}</h2>
        <p>Firmware ranked for ${p.model.key || "this Mac"}${({ lvds: " (LVDS display)", edp: " (eDP display)" })[p.model.panel] || ""}. Native GOP comes first; anything that can’t work here is locked.</p></div></div>
    ${when(p.cards.length > 1, () => section("Which card is installed?", html`<div class="segmented">${p.cards.map((x, i) =>
      html`<button class="${i === g.cardIdx ? "on" : ""}" data-act="gpu-card" data-i="${i}">${x.name.replace(/^AMD (Radeon Pro |FirePro |Radeon )?/, "").replace(/\s*\(.*\)$/, "")}</button>`)}</div>`,
      bestCardIndex(p.cards, selectedGpu()?.name || "") >= 0
        ? `These cards share one PCI ID. Pre-selected from the name your card reports (“${gpuName(selectedGpu()?.name)}”) — change it if that’s wrong.`
        : "These cards share the same PCI ID, so GopForge Live can’t tell them apart on its own — pick the one installed."))}
    ${backlightCallout(c, p)}
    ${when(c.notes, () => html`<div class="section">${callout(noteKind, c.hot ? "Runs hot" : c.memory_variants ? "Match your memory vendor" : "About this card", c.notes)}</div>`)}
    ${when(p.model.note, () => html`<div style="margin-top:var(--s3)">${callout("info", p.model.key, p.model.note, "imac")}</div>`)}
    ${groups.map(([t, list]) => section(t, html`<div class="group">${list.map((r) => romRow(r, r === rec))}</div>`))}
    <div class="btn-row">
      <button class="btn" data-act="gpu-back">${icon("chevronLeft")} Back</button><span class="grow"></span>
      <button class="btn primary large" data-act="gpu-next" ${g.rom ? "" : "disabled"}>Continue ${icon("chevronRight")}</button>
    </div>
  </div>`;
}

function viewBackup() {
  const g = G(); const a = g.adapters; const gpu = selectedGpu();
  const j = myJob("backup-gpu");
  const open = !!S.ui.console.adapters;
  return html`<div class="panel">
    <div class="panel-head"><div style="width:84px;height:84px;flex:none">${gpuArt()}</div>
      <div class="txt"><h2 class="t-title2">Back up the current firmware</h2>
        <p>Before anything is written, the card’s existing firmware is saved to this USB. It’s the only way to undo the change, so keep it.</p></div></div>
    ${!a ? html`<p class="muted">Reading adapters…</p>` : !a.ok ? callout("danger", "Couldn’t list the adapters", a.error) : html`
      ${section("Adapter", html`<div class="group"><div class="row">
        ${sq("gpu", gpu.flasher === "nvidia" ? "green" : "red")}
        <div class="main-col"><div class="title">${gpuName(gpu.name)}</div><div class="subtitle">${gpu.flasher === "amd" ? "amdvbflash" : "nvflash"} adapter</div></div>
        ${a.indices.length > 1 ? html`<div class="segmented">${a.indices.map((i) => html`<button class="${i === g.adapter ? "on" : ""}" data-act="gpu-adapter" data-i="${i}">#${i}</button>`)}</div>`
          : html`<span class="value">#${g.adapter}</span>`}
      </div></div>`, a.indices.length > 1 ? "More than one adapter found — pick the one whose bus matches the card above." : "")}
      <button class="disclose ${open ? "open" : ""}" data-act="toggle-console" data-id="adapters">${icon("chevronRight")} ${open ? "Hide" : "Show"} Adapter List</button>
      <div class="console" ${open ? "" : "hidden"}>${a.raw}</div>`}
    ${jobBlock(j, { running: "Saving the current firmware…", done: "Backup saved", failed: "Backup failed" })}
    ${when(g.backup, () => html`<div style="margin-top:var(--s5)">${fileCard(g.backup, "vbios")}</div>`)}
    <div class="btn-row">
      <button class="btn" data-act="gpu-back" ${jobRunning() ? "disabled" : ""}>${icon("chevronLeft")} Back</button><span class="grow"></span>
      <button class="btn primary large" data-act="gpu-backup" ${a?.ok && !jobRunning() ? "" : "disabled"}>${icon("download")} Back Up Current Firmware</button>
    </div>
  </div>`;
}

function viewFlash() {
  const g = G(); const gpu = selectedGpu(); const j = myJob("flash-gpu");
  return html`<div class="panel">
    <div class="panel-head"><div style="width:84px;height:84px;flex:none">${gpuArt()}</div>
      <div class="txt"><h2 class="t-title2">Ready to flash</h2><p>Review what will be written. You’ll be asked to confirm before anything changes.</p></div></div>
    <div class="group">
      <div class="row">${sq("gpu", "red")}<div class="main-col"><div class="title">Card</div><div class="subtitle">${gpuName(gpu.name)} · adapter #${g.adapter}</div></div></div>
      <div class="row">${methodBadge(g.rom.method)}<div class="main-col"><div class="title">New firmware</div><div class="subtitle">${romTitle(g.rom.file)} · ${method(g.rom.method).name}</div></div>${status(blocked(g.rom) ? "bad" : g.rom.marker.level)}</div>
      <div class="row">${sq("archive", "blue")}<div class="main-col"><div class="title">Your backup</div><div class="subtitle">${g.backup.name} · <span class="mono">${shortHash(g.backup.sha256)}</span></div></div>${status("ok")}</div>
    </div>
    ${when(blocked(g.rom), () => html`<div style="margin-top:var(--s4)">${callout("danger", "Expert override", `${g.rom.marker.text}. You’ve chosen it with Expert Mode on.`)}</div>`)}
    ${backlightCallout(card(), g.plan, "inline")}
    <div style="margin-top:var(--s4)">${callout("warn", "If the screen stays dark afterwards",
      html`Boot this USB again with another graphics card (or connect over SSH — user <span class="mono">root</span>, password <span class="mono">flash</span>) and restore <span class="mono">${g.backup.name}</span>.`)}</div>
    ${jobBlock(j, { running: "Flashing…", done: "Firmware written", failed: "Flashing failed" })}
    <div class="btn-row">
      <button class="btn" data-act="gpu-back" ${jobRunning() ? "disabled" : ""}>${icon("chevronLeft")} Back</button><span class="grow"></span>
      <button class="btn destructive large" data-act="gpu-flash" ${jobRunning() ? "disabled" : ""}>${icon("bolt")} Flash Graphics Firmware…</button>
    </div>
  </div>`;
}

function viewFinish() {
  const g = G(); const gpu = selectedGpu();
  const restore = gpu.flasher === "amd" ? `amdvbflash -f -p ${g.adapter} ${g.backup.name}` : `nvflash -i${g.adapter} -6 ${g.backup.name}`;
  const tip = (n, t, d) => html`<div class="row"><span class="sq bg-blue" style="font-weight:700;font-size:13px">${n}</span>
    <div class="main-col"><div class="title">${t}</div><div class="subtitle">${d}</div></div></div>`;
  return html`<div class="panel">
    <div style="text-align:center">
      <div style="display:grid;place-items:center;margin:4px 0 14px">${successArt()}</div>
      <h2 class="t-title1">Graphics firmware updated</h2>
      <p class="muted" style="margin:8px auto 0;max-width:56ch;line-height:1.5">${romTitle(g.rom.file)} is now on your ${gpuName(gpu.name)}.</p>
    </div>
    ${section("Next steps", html`<div class="group icons">
      ${tip(1, "Shut down completely", "Graphics firmware only reloads after a full power cycle.")}
      ${tip(2, "Power on", card()?.backlight_addon === "yes"
        ? "The boot screen should now appear on the built-in display — with the backlight add-on fitted. Without it the screen stays dark until macOS starts."
        : "The boot screen should now appear on the built-in display.")}
      ${tip(3, "Hold ⌥ Option for the startup picker", "Use it to choose between macOS installs or this USB.")}
    </div>`, html`To undo, boot this USB and run <span class="mono">${restore}</span>.`)}
    <div class="btn-row">
      <button class="btn" data-act="go" data-to="backups">${icon("archive")} View Backups</button><span class="grow"></span>
      <button class="btn primary large" data-act="system" data-do="poweroff">${icon("power")} Shut Down</button>
    </div>
  </div>`;
}

export function render() {
  const m = S.status.machine;
  if (!(m.allow_gpu || S.status.expert))
    return html`<div class="page">${locked("Graphics firmware tools are for iMacs",
      html`Supported: iMac 2009 – 2011 (iMac9,1 to iMac12,2). ${m.class === "cmp-bootrom" ? "Your Mac Pro gets its boot screen from the Boot ROM instead." : ""}`)}</div>`;
  const s = G().flashed ? "finish" : G().step;
  const body = { card: viewCard, firmware: viewFirmware, backup: viewBackup, flash: viewFlash, finish: viewFinish }[s]();
  return html`<div class="page">
    <div class="page-head">
      <h1 class="t-large">Graphics Card</h1>
      <p>Give your iMac a native boot screen by installing GOP-enabled firmware on its graphics card — chosen for your exact card and display.</p>
    </div>
    ${steps(STEPS, s)}
    ${body}
  </div>`;
}
