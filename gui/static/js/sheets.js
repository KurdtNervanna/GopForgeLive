// sheets.js — modal sheets and popover menus.
import { html, raw, when } from "./dom.js";
import { icon, sq, spinner } from "./icons.js";
import { appIcon, cautionArt } from "./art.js";
import { api } from "./api.js";
import { S, actions, update, openSheet, closeSheet, closeMenu, toast, refreshStatus, setTheme, setSize, jobRunning } from "./core.js";

const ARM_MS = 3000;

// ------------------------------------------------------------------ renders --
function confirmSheet(sh) {
  sh.armAt ??= Date.now() + ARM_MS;
  sh.typed ??= "";
  const ready = sh.typed.trim() === sh.phrase;
  const left = Math.ceil((sh.armAt - Date.now()) / 1000);
  return html`<div class="sheet" role="alertdialog" aria-modal="true" aria-labelledby="sheet-title">
    ${cautionArt(sh.tone === "danger" ? "#ff453a" : "#ff9f0a")}
    <div class="s-title" id="sheet-title">${sh.title}</div>
    <div class="s-body">${sh.body}</div>
    ${when(sh.rows?.length, () => html`<div class="group">${sh.rows.map(([k, v]) => html`
      <div class="row" style="min-height:40px"><div class="main-col"><div class="subtitle" style="margin:0">${k}</div></div>
      <div class="value select-text" style="color:var(--label);max-width:70%;overflow-wrap:anywhere;text-align:right">${v}</div></div>`)}</div>`)}
    <label class="confirm-label" for="confirm-field">To confirm, type <span class="mono">${sh.phrase}</span></label>
    <input id="confirm-field" class="field ${ready ? "match" : ""}" data-input="confirm" autocomplete="off" spellcheck="false" value="${sh.typed}" placeholder="${sh.phrase}">
    <div class="btn-row">
      <button class="btn" data-act="close-sheet">Cancel</button>
      <button class="btn ${sh.tone === "danger" ? "destructive" : "primary"}" id="confirm-go" data-act="confirm-go" ${ready && left <= 0 ? "" : "disabled"}>
        ${sh.action}${left > 0 ? ` (${left})` : ""}</button>
    </div>
  </div>`;
}

function expertSheet() {
  const on = S.status?.expert;
  const sh = S.sheet; sh.typed ??= "";
  const ready = sh.typed.trim().toUpperCase() === "I UNDERSTAND";
  return html`<div class="sheet" role="dialog" aria-modal="true">
    <div style="margin-bottom:12px">${sq("wrench", "orange", "xl")}</div>
    <div class="s-title">${on ? "Expert Mode is on" : "Turn on Expert Mode?"}</div>
    <div class="s-body">${on
      ? "Every tool is unlocked regardless of the detected Mac, and firmware marked “won’t work on this Mac” can be selected."
      : html`Expert Mode removes GopForge Live’s <strong>machine gating</strong> and lets you pick firmware that is known
          <strong>not to work</strong> on this Mac. Backups and typed confirmations are still required.
          Use it only if you know exactly what you’re doing — for example, pre-flashing a card in another computer.`}</div>
    ${when(!on, () => html`
      <label class="confirm-label" for="expert-field">Type <span class="mono">I UNDERSTAND</span> to continue</label>
      <input id="expert-field" class="field ${ready ? "match" : ""}" data-input="expert" autocomplete="off" spellcheck="false" value="${sh.typed}" placeholder="I UNDERSTAND">`)}
    <div class="btn-row">
      <button class="btn" data-act="close-sheet">${on ? "Close" : "Cancel"}</button>
      ${on ? html`<button class="btn primary" data-act="expert-off">Turn Off Expert Mode</button>`
           : html`<button class="btn destructive" id="expert-go" data-act="expert-on" ${ready ? "" : "disabled"}>Turn On</button>`}
    </div>
  </div>`;
}

function settingsSheet() {
  const seg = (act, cur, opts) => html`<div class="segmented">${opts.map(([v, l]) =>
    html`<button class="${cur === v ? "on" : ""}" data-act="${act}" data-v="${v}">${l}</button>`)}</div>`;
  const st = S.status;
  return html`<div class="sheet" role="dialog" aria-modal="true">
    <div style="display:flex;align-items:center;gap:14px;margin-bottom:6px">
      <div style="width:52px;height:52px">${appIcon()}</div>
      <div><div class="s-title">GopForge Live</div><div class="t-footnote muted">Version ${st?.version || "—"}${st?.mock ? " · demo mode" : ""}</div></div>
    </div>
    <div class="group" style="margin-top:18px">
      <div class="row">${sq("moon", "indigo")}<div class="main-col"><div class="title">Appearance</div></div>
        ${seg("theme", S.theme, [["light", "Light"], ["dark", "Dark"]])}</div>
      <div class="row">${sq("eye", "blue")}<div class="main-col"><div class="title">Text Size</div></div>
        ${seg("size", S.size, [["default", "Default"], ["large", "Large"], ["larger", "Larger"]])}</div>
      <div class="row">${sq("wrench", "orange")}<div class="main-col"><div class="title">Expert Mode</div><div class="subtitle">Remove machine gating</div></div>
        <button class="switch danger ${st?.expert ? "on" : ""}" data-act="sheet" data-sheet="expert" aria-label="Expert Mode" role="switch" aria-checked="${!!st?.expert}"></button></div>
      <div class="row link" tabindex="0" role="button" data-act="system" data-do="textmode">${sq("terminal", "graphite")}
        <div class="main-col"><div class="title">Switch to Text Mode</div><div class="subtitle">The classic keyboard wizard</div></div>${icon("chevronRight", "chev")}</div>
    </div>
    <div class="section-foot" style="margin:14px 2px 0;line-height:1.5">
      Built on GRML-FLASH (Ausdauersportler), the IMAC-EFI-BOOT-SCREEN firmware collection (GPL-3.0), GopForge, and
      acidanthera’s EnableGop. Not affiliated with Apple. Inter &amp; JetBrains Mono fonts under the SIL OFL.
    </div>
    <div class="btn-row"><button class="btn primary" data-act="close-sheet">Done</button></div>
  </div>`;
}

function hardwareSheet() {
  const h = S.hardware;
  const done = html`<div class="btn-row"><button class="btn primary" data-act="close-sheet">Done</button></div>`;
  if (!h) return html`<div class="sheet wide" role="dialog" aria-modal="true">
    <div class="s-title">Hardware Report</div>
    <div class="s-body">${spinner()} Collecting everything about this computer — processors, memory, graphics, Wi-Fi, Bluetooth, drives… This can take up to a minute.</div>${done}</div>`;
  if (h.error || !h.system) return html`<div class="sheet wide" role="dialog" aria-modal="true">
    <div class="s-title">Hardware Report</div>
    <div class="s-body">${h.error || "Only a basic report was available."}</div>
    ${when(h.text, () => html`<div class="console" style="max-height:52vh;margin-top:16px">${h.text}</div>`)}${done}</div>`;
  const line = (items, f) => (items && items.length ? items.map(f).join("\n") : "None detected");
  const cpuGroups = {};
  (h.cpus || []).forEach((c) => { (cpuGroups[c.name] ??= []).push(c); });
  const cpus = Object.entries(cpuGroups).map(([n, cs]) =>
    `${cs.length} × ${n}${cs[0].cores ? ` · ${cs[0].cores} cores${cs[0].threads ? ` / ${cs[0].threads} threads` : ""} each` : ""}`).join("\n") || "—";
  const m = h.memory || {};
  const mem = `${m.total || "—"}${m.slots ? ` · ${m.slots_used} of ${m.slots} slots used` : ""}${m.max_capacity ? ` · max ${m.max_capacity}` : ""}`;
  const mods = (m.modules || []).map((d) => `${d.slot}: ${d.size} ${d.type} ${d.speed} ${d.manufacturer} ${d.part}`.replace(/\s+/g, " ").trim());
  const row = (label, value) => html`<div class="row" style="align-items:flex-start"><div class="main-col"><div class="subtitle" style="margin:0">${label}</div>
    <div class="title select-text" style="white-space:pre-line;font-weight:500">${value}</div></div></div>`;
  const open = !!S.ui.console.hwfull;
  return html`<div class="sheet wide" role="dialog" aria-modal="true">
    <div class="s-title">Hardware Report</div>
    <div class="s-body">${h.saved
      ? html`Saved to the USB: <span class="mono select-text">${h.saved.replace(/^.*\/gopforge-live\//, "gopforge-live/")}</span>. It includes serial numbers and MAC addresses — share it with care.`
      : "Not saved — the USB isn’t writable."}</div>
    <div class="group" style="margin-top:16px">
      ${row("Model", `${h.system.model || "—"}${h.system.board ? ` · ${h.system.board}` : ""}`)}
      ${row("Boot ROM", `${h.bootrom.version || "—"}${h.bootrom.date ? ` (${h.bootrom.date})` : ""}`)}
      ${row("Processors", cpus)}
      ${row("Memory", [mem, ...mods].join("\n"))}
      ${row("Graphics", line(h.graphics, (d) => `${d.name}${d.driver ? ` · ${d.driver}` : ""}`))}
      ${row("Wi-Fi", line(h.wifi, (d) => d.name))}
      ${row("Bluetooth", line(h.bluetooth, (d) => d.name))}
      ${row("Ethernet", line(h.ethernet, (d) => d.name))}
      ${row("Storage", line(h.storage, (d) => `${d.name} · ${d.size} ${d.kind}${d.model ? ` · ${d.model}` : ""}${d.transport ? ` (${d.transport})` : ""}`))}
    </div>
    <button class="disclose ${open ? "open" : ""}" data-act="toggle-console" data-id="hwfull" style="margin-top:12px">${icon("chevronRight")} ${open ? "Hide" : "Show"} Full Report</button>
    <div class="console" ${open ? "" : "hidden"} style="max-height:40vh">${h.text}</div>
    ${done}
  </div>`;
}

function alertSheet(sh) {
  return html`<div class="sheet" role="alertdialog" aria-modal="true">
    <div style="margin-bottom:12px">${sq(sh.icon || "power", sh.color || "gray", "xl")}</div>
    <div class="s-title">${sh.title}</div>
    <div class="s-body">${sh.body}</div>
    <div class="btn-row">
      <button class="btn" data-act="close-sheet">Cancel</button>
      <button class="btn ${sh.tone === "danger" ? "destructive" : "primary"}" data-act="alert-go">${sh.action}</button>
    </div>
  </div>`;
}

export function renderSheet() {
  const sh = S.sheet;
  if (!sh) return "";
  const body = { confirm: confirmSheet, expert: expertSheet, settings: settingsSheet, hardware: hardwareSheet, alert: alertSheet }[sh.kind]?.(sh) || "";
  return html`<div class="scrim" data-act="scrim">${body}</div>`;
}

export function renderMenu() {
  const m = S.menu;
  if (!m || m.kind !== "power") return "";
  return html`<div class="menu" style="left:${m.x}px;top:${m.y}px" role="menu">
    <button role="menuitem" data-act="system" data-do="reboot">${icon("restart")} Restart…</button>
    <button role="menuitem" data-act="system" data-do="poweroff">${icon("power")} Shut Down…</button>
    <hr>
    <button role="menuitem" data-act="system" data-do="textmode">${icon("terminal")} Switch to Text Mode</button>
  </div>`;
}

export function renderHud() {
  const j = S.job;
  if (S.powering) return html`<div class="hud-scrim"><div class="hud">
    <div class="h-icon" style="display:grid;place-items:center;color:#fff">${spinner()}</div>
    <div class="h-title">${S.powering}</div><div class="h-sub">You can remove the USB once the screen goes dark.</div></div></div>`;
  if (!j || !j.hud || j.state !== "running") return "";
  const last = j.lines.length ? j.lines[j.lines.length - 1].replace(/^\d\d:\d\d:\d\d \[\w+\] /, "") : "Starting…";
  return html`<div class="hud-scrim" role="alertdialog" aria-modal="true" aria-live="polite"><div class="hud">
    <div class="h-icon">${sq("bolt", "orange", "xl")}</div>
    <div class="h-title">${j.title}</div>
    <div class="h-sub">${j.sub || "Please wait."} · <span data-since="${j.started}">0:00</span></div>
    <div class="progress indeterminate"><i></i></div>
    <div class="h-line" id="hud-line">${last}</div>
    <div class="h-warn">${icon("alert")} Don’t turn off your Mac or remove the USB</div>
  </div></div>`;
}

// -------------------------------------------------------- live input patching --
export function onInput(el) {
  const sh = S.sheet;
  if (!sh) return false;
  if (el.dataset.input === "confirm") {
    sh.typed = el.value;
    const ready = sh.typed.trim() === sh.phrase;
    el.classList.toggle("match", ready);
    const go = document.getElementById("confirm-go");
    if (go) go.disabled = !(ready && Date.now() >= sh.armAt);
    return true;
  }
  if (el.dataset.input === "expert") {
    sh.typed = el.value;
    const ready = sh.typed.trim().toUpperCase() === "I UNDERSTAND";
    el.classList.toggle("match", ready);
    const go = document.getElementById("expert-go");
    if (go) go.disabled = !ready;
    return true;
  }
  return false;
}

// Count down the arm delay without re-rendering (keeps the caret in the field).
setInterval(() => {
  const sh = S.sheet;
  if (!sh || sh.kind !== "confirm") return;
  const go = document.getElementById("confirm-go");
  if (!go) return;
  const left = Math.ceil((sh.armAt - Date.now()) / 1000);
  go.textContent = `${sh.action}${left > 0 ? ` (${left})` : ""}`;
  go.disabled = !(sh.typed.trim() === sh.phrase && left <= 0);
}, 200);

// ------------------------------------------------------------------ actions --
async function systemDo(what) {
  closeMenu();
  const labels = {
    poweroff: ["Shut down now?", "Your backups are already saved on the USB.", "Shut Down", "power", "red"],
    reboot: ["Restart now?", "Hold ⌥ Option while it starts to choose a startup disk.", "Restart", "restart", "blue"],
    textmode: ["Switch to text mode?", "The graphical app closes and the keyboard-driven wizard starts in its place.", "Switch", "terminal", "graphite"],
  }[what];
  if (!labels) return;
  if (jobRunning()) { toast("warn", "Please wait", "An operation is still running."); return; }
  openSheet({
    kind: "alert", title: labels[0], body: labels[1], action: labels[2], icon: labels[3], color: labels[4],
    run: async () => {
      const r = await api.post("/api/system", { action: what });
      if (!r.ok) return toast("bad", "Couldn’t do that", r.error);
      if (r.mock) return toast("info", "Demo mode", `On a real Mac this would ${labels[2].toLowerCase()}.`);
      if (what !== "textmode") update({ powering: what === "reboot" ? "Restarting…" : "Shutting down…" });
    },
  });
}

Object.assign(actions, {
  "close-sheet": closeSheet,
  scrim: (el, e) => { if (e.target === el && S.sheet?.kind !== "confirm") closeSheet(); },
  sheet: async (el) => {
    const kind = el.dataset.sheet;
    openSheet({ kind });
    if (kind === "hardware") {
      S.hardware = null;
      const h = await api.get("/api/hardware");
      update({ hardware: h.ok ? h : { error: h.error || "The report couldn’t be collected." } });
    }
  },
  "confirm-go": () => {
    const sh = S.sheet;
    if (!sh || sh.typed.trim() !== sh.phrase || Date.now() < sh.armAt) return;
    closeSheet();
    sh.onConfirm(sh.phrase);
  },
  "alert-go": () => { const sh = S.sheet; closeSheet(); sh?.run?.(); },
  "expert-on": async () => {
    const r = await api.post("/api/expert", { enable: true, phrase: S.sheet?.typed || "" });
    if (!r.ok) return toast("bad", "Expert Mode", r.error);
    closeSheet(); await refreshStatus();
    toast("warn", "Expert Mode is on", "Machine gating is disabled for this session.");
  },
  "expert-off": async () => {
    await api.post("/api/expert", { enable: false });
    closeSheet(); await refreshStatus();
    toast("info", "Expert Mode is off");
  },
  theme: (el) => setTheme(el.dataset.v),
  size: (el) => setSize(el.dataset.v),
  system: (el) => systemDo(el.dataset.do),
});
