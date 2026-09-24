// app.js — shell, routing, rendering and event wiring.
import { html, raw, when, $ } from "./dom.js";
import { icon, sq, spinner, status as stIcon } from "./icons.js";
import { appIcon } from "./art.js";
import { S, actions, update, setRenderer, applyPrefs, navigate, refreshStatus, openMenu, closeMenu, closeSheet, setTheme, jobRunning, persist } from "./core.js";
import { renderSheet, renderMenu, renderHud, onInput as sheetInput } from "./sheets.js";
import { macInfo } from "./macs.js";
import * as overview from "./views/overview.js";
import * as bootrom from "./views/bootrom.js";
import * as gpu from "./views/gpu.js";
import * as backups from "./views/backups.js";
import * as library from "./views/library.js";
import * as activity from "./views/activity.js";

const VIEWS = { overview, bootrom, gpu, backups, library, activity };

// ------------------------------------------------------------------ sidebar --
function navItem(route, ic, color, label, { meta = "", locked = false } = {}) {
  const on = S.route === route;
  return html`<button id="nav-${route}" class="nav-item ${on ? "active" : ""} ${locked ? "locked" : ""}" data-act="go" data-to="${route}" aria-current="${on ? "page" : "false"}">
    ${sq(ic, locked ? "gray" : color)}<span class="nav-label">${label}</span>
    ${when(locked, () => html`<span class="nav-meta">${icon("lock")}</span>`, () => when(meta, () => html`<span class="nav-meta">${meta}</span>`))}
  </button>`;
}

function sidebar() {
  const st = S.status; const m = st.machine; const ex = st.expert;
  const info = macInfo(m.model);
  const running = jobRunning();
  return html`
    <div class="brand">${appIcon()}<div><div class="name">GopForge Live</div><div class="sub">Boot Screen Utility</div></div></div>
    <div class="nav-section"><div class="nav-title">This Mac</div>
      ${navItem("overview", /^iMac/.test(m.model) ? "imac" : "macpro", "graphite", info.name, { meta: m.model })}
    </div>
    <div class="nav-section"><div class="nav-title">Boot Screen</div>
      ${navItem("bootrom", "chip", "orange", "Boot ROM", { locked: !(m.allow_bootrom || ex) })}
      ${navItem("gpu", "gpu", "purple", "Graphics Card", { locked: !(m.allow_gpu || ex) })}
    </div>
    <div class="nav-section"><div class="nav-title">Library</div>
      ${navItem("backups", "archive", "blue", "Backups", { meta: S.backups?.files ? String(S.backups.files.length) : "" })}
      ${navItem("library", "layers", "indigo", "ROM Library", { meta: String(st.library.roms) })}
      ${navItem("activity", "terminal", "graphite", "Activity", { meta: running ? spinner() : "" })}
    </div>
    <div class="sidebar-foot">
      <div class="storage-chip"><span class="dot ${st.storage.on_usb ? "green" : "orange"}"></span>
        <span>${st.storage.on_usb ? "Saving backups to the USB" : "No writable USB — memory only"}</span></div>
      ${when(ex, () => html`<div class="storage-chip"><span class="dot orange"></span><span>Expert Mode on</span></div>`)}
      <div class="foot-row"><span class="t-caption faint">v${st.version}</span>
        <span><button class="btn icon" data-act="sheet" data-sheet="settings" title="Settings">${icon("sliders")}</button></span></div>
    </div>`;
}

// ------------------------------------------------------------------ toolbar --
function toolbar() {
  const v = VIEWS[S.route];
  const j = S.job;
  return html`
    <div><div class="tb-title">${v.title}</div></div>
    <div class="spacer"></div>
    ${when(j && j.state === "running" && !j.hud, () => html`<span class="pill">${spinner()} ${j.title}</span>`)}
    ${when(S.status.mock, () => html`<span class="pill purple">${icon("sparkle")} Demo</span>`)}
    <button class="btn icon" data-act="toggle-theme" title="Appearance">${icon(S.theme === "dark" ? "sun" : "moon")}</button>
    <button class="btn icon" data-act="sheet" data-sheet="settings" title="Settings">${icon("sliders")}</button>
    <button class="btn icon" data-act="power-menu" title="Power">${icon("power")}</button>`;
}

function toasts() {
  return html`${S.toasts.map((t) => html`<div class="toast" id="toast-${t.id}" role="status">
    ${stIcon(t.level)}<div><div class="t-title">${t.title}</div>${when(t.body, () => html`<div class="t-body">${t.body}</div>`)}</div></div>`)}`;
}

function splash(err) {
  return html`<div class="wallpaper"></div><div class="splash"><div>
    ${appIcon()}
    <div class="title">GopForge Live</div>
    <div class="sub">${err || "Getting to know this Mac…"}</div>
    ${err ? html`<div class="btn-row" style="justify-content:center"><button class="btn primary" data-act="retry">Try Again</button></div>`
          : html`<div class="progress indeterminate"><i></i></div>`}
  </div></div>`;
}

// ------------------------------------------------------------------- render --
const last = {};
function patch(id, content) {
  const s = String(content);
  if (last[id] === s) return false;
  const el = document.getElementById(id);
  if (!el) return false;
  el.innerHTML = s; last[id] = s;
  return true;
}

function render() {
  const root = document.getElementById("root");
  if (S.booting || !S.status) {
    const s = String(splash(S.error));
    if (last.root !== s) { root.innerHTML = s; last.root = s; }
    return;
  }
  if (!document.getElementById("page")) {
    root.innerHTML = `<div class="wallpaper"></div>
      <div class="app"><aside class="sidebar" id="sidebar" aria-label="Sidebar"></aside>
      <div class="main"><header class="toolbar" id="toolbar"></header>
      <div class="scroller" id="scroller"><main id="page"></main></div></div></div>
      <div id="overlay"></div><div id="hud"></div><div class="toasts" id="toasts" aria-live="polite"></div>`;
    for (const k of Object.keys(last)) delete last[k];
  }
  // keep focus + caret across re-renders
  const a = document.activeElement;
  const keep = a && a.id ? { id: a.id, s: a.selectionStart, e: a.selectionEnd } : null;

  patch("sidebar", sidebar());
  patch("toolbar", toolbar());
  patch("page", VIEWS[S.route].render());
  patch("overlay", html`${renderSheet()}${renderMenu()}`);
  patch("hud", renderHud());
  patch("toasts", toasts());
  persist();

  if (keep) {
    const el = document.getElementById(keep.id);
    if (el && el !== document.activeElement) {
      el.focus();
      try { if (keep.s != null) el.setSelectionRange(keep.s, keep.e); } catch { /* not a text field */ }
    }
  }
  // autofocus fields inside a freshly opened sheet
  if (S.sheet && !S.sheet._focused) {
    const f = document.querySelector("#overlay .field") || document.querySelector("#overlay .btn.primary, #overlay .btn.destructive");
    if (f) { f.focus(); S.sheet._focused = true; }
  }
}
setRenderer(render);

// ------------------------------------------------------------------- routing --
async function route() {
  const r = (location.hash.replace(/^#\/?/, "") || "overview").split("?")[0];
  const next = VIEWS[r] ? r : "overview";
  const changed = next !== S.route;
  S.route = next; closeMenu();
  update();
  if (changed) { const sc = document.getElementById("scroller"); if (sc) sc.scrollTop = 0; }
  await VIEWS[next].enter?.();
}
window.addEventListener("hashchange", route);

// ------------------------------------------------------------------- events --
Object.assign(actions, {
  go: (el, e) => { e.preventDefault?.(); navigate(el.dataset.to); },
  "toggle-console": (el) => { const id = el.dataset.id; S.ui.console[id] = !S.ui.console[id]; update(); },
  "toggle-theme": () => setTheme(S.theme === "dark" ? "light" : "dark"),
  "power-menu": (el) => (S.menu ? closeMenu() : openMenu("power", el)),
  retry: () => boot(),
});

document.addEventListener("click", (e) => {
  const el = e.target.closest("[data-act]");
  if (S.menu && !e.target.closest(".menu") && !(el && el.dataset.act === "power-menu")) closeMenu();
  if (!el) return;
  const fn = actions[el.dataset.act];
  if (fn) { if (el.tagName === "A") e.preventDefault(); fn(el, e); }
});

document.addEventListener("input", (e) => {
  const el = e.target;
  if (!el.dataset || !el.dataset.input) return;
  if (sheetInput(el)) return;
  if (library.onInput(el)) return;
});

document.addEventListener("keydown", (e) => {
  if (e.key === "Escape") {
    if (S.menu) { closeMenu(); return; }
    if (S.sheet && !(S.job && S.job.hud && S.job.state === "running")) { closeSheet(); return; }
  }
  if (e.key === "Enter" && e.target.id === "confirm-field") { actions["confirm-go"]?.(); return; }
  if (e.key === "Enter" && e.target.id === "expert-field") { actions["expert-on"]?.(); return; }
  // keyboard activation for role=button / radio rows
  if ((e.key === "Enter" || e.key === " ") && e.target.matches?.('[tabindex="0"][data-act]')) {
    e.preventDefault(); e.target.click();
  }
});

// Block accidental navigation away (the kiosk has no chrome, but just in case).
window.addEventListener("beforeunload", (e) => { if (jobRunning()) { e.preventDefault(); e.returnValue = ""; } });

// --------------------------------------------------------------------- boot --
async function boot() {
  applyPrefs();
  S.booting = true; S.error = null; update();
  const t0 = Date.now();
  let s;
  for (let i = 0; i < 40; i++) {           // the backend may still be starting
    s = await refreshStatus();
    if (s.ok) break;
    await new Promise((r) => setTimeout(r, 500));
  }
  await new Promise((r) => setTimeout(r, Math.max(0, 700 - (Date.now() - t0))));
  if (!s || !s.ok) { S.booting = false; S.status = null; update({ error: s?.error || "The backend didn’t respond." }); return; }
  S.booting = false;
  await route();
}
boot();
