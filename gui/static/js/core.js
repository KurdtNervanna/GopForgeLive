// core.js — global state, render scheduling, jobs, sheets, menus, toasts.
// Views import from here (never from app.js) to keep module loading acyclic.
import { api } from "./api.js";
import { consoleLine } from "./dom.js";

const pref = (k, d) => { try { return localStorage.getItem(k) || d; } catch { return d; } };
const savePref = (k, v) => { try { localStorage.setItem(k, v); } catch { /* ignore */ } };

export const S = {
  booting: true,
  status: null,            // /api/status
  error: null,
  route: "overview",
  theme: pref("gfl-theme", "dark"),
  size: pref("gfl-size", "default"),
  ui: { console: {} },     // disclosure state etc.
  gpus: null,
  hardware: null,
  // Boot ROM flow
  br: { dump: null, facts: null, report: "", checked: false, variant: "standard", patched: null, pfacts: null, written: false, error: null },
  // Graphics flow
  gpu: { step: "card", gpuIndex: null, model: null, modelKey: null, plan: null, cardIdx: 0, rom: null,
         adapters: null, adapter: null, backup: null, flashed: false, error: null },
  backups: null,
  library: null,
  libFilter: { q: "", method: "all" },
  log: null,
  job: null,               // current/last job
  sheet: null,             // { kind, ... }
  menu: null,              // { kind, x, y }
  toasts: [],
};

// Keep flow progress across a reload / browser restart within this boot.
try {
  const saved = JSON.parse(sessionStorage.getItem("gfl-flow") || "null");
  if (saved) { Object.assign(S.br, saved.br || {}); Object.assign(S.gpu, saved.gpu || {}); }
} catch { /* ignore */ }
export function persist() {
  try { sessionStorage.setItem("gfl-flow", JSON.stringify({ br: S.br, gpu: S.gpu })); } catch { /* ignore */ }
}

export const actions = {};          // "name" -> (el, event) => void
let renderFn = () => {};
export const setRenderer = (fn) => { renderFn = fn; };

// Batch renders in a microtask (not requestAnimationFrame, which is paused while
// a tab is hidden — rendering must never depend on visibility).
let pending = false;
export function update(patch) {
  if (patch) Object.assign(S, patch);
  if (!pending) {
    pending = true;
    Promise.resolve().then(() => { pending = false; renderFn(); });
  }
}

export function setTheme(t) { S.theme = t; savePref("gfl-theme", t); applyPrefs(); update(); }
export function setSize(s) { S.size = s; savePref("gfl-size", s); applyPrefs(); update(); }
export function applyPrefs() {
  document.documentElement.dataset.theme = S.theme;
  document.documentElement.dataset.size = S.size;
}

export function navigate(route) {
  if (location.hash !== `#/${route}`) location.hash = `#/${route}`;
  else update({ route });
}

// ---------------------------------------------------------------- toasts --
let toastId = 0;
export function toast(level, title, body = "", ms = 5200) {
  const t = { id: ++toastId, level, title, body };
  S.toasts = [...S.toasts, t].slice(-4);
  update();
  setTimeout(() => {
    const el = document.getElementById(`toast-${t.id}`);
    if (el) el.classList.add("out");
    setTimeout(() => { S.toasts = S.toasts.filter((x) => x.id !== t.id); update(); }, 260);
  }, ms);
}

// ------------------------------------------------------------ sheets/menus --
export function openSheet(sheet) { S.menu = null; update({ sheet }); }
export function closeSheet() { update({ sheet: null }); }
export function openMenu(kind, anchor) {
  const r = anchor.getBoundingClientRect();
  update({ menu: { kind, x: Math.max(8, r.right - 232), y: r.bottom + 6 } });
}
export function closeMenu() { if (S.menu) update({ menu: null }); }

// ------------------------------------------------------------------- data --
export async function refreshStatus() {
  const s = await api.get("/api/status");
  if (s.ok) update({ status: s, error: null });
  else update({ error: s.error || "Could not read the system status." });
  return s;
}

// ------------------------------------------------------------------- jobs --
export const jobRunning = () => !!(S.job && S.job.state === "running");

/**
 * Start a backend job and stream it. Resolves with the finished job
 * ({state: done|failed|refused, result}) or null if it could not start.
 */
export async function runJob(action, args = {}, opts = {}) {
  if (jobRunning()) { toast("warn", "Please wait", `“${S.job.title || S.job.action}” is still running.`); return null; }
  const r = await api.post("/api/jobs", { action, args, confirm: opts.confirm });
  if (!r.ok) { toast("bad", opts.failTitle || "Couldn’t start", r.error || "Unknown error"); return null; }
  const job = { ...r.job, lines: [...(r.job.lines || [])], owner: opts.owner || "", hud: !!opts.hud,
                title: opts.title || action, sub: opts.sub || "" };
  S.job = job;
  S.ui.console[job.id] = false;
  update();
  return new Promise((resolve) => {
    const tick = async () => {
      const j = await api.get(`/api/jobs/${job.id}?since=${job.lines.length}`);
      if (j.ok) {
        const v = j.job;
        if (v.lines.length) { job.lines.push(...v.lines); streamLines(job, v.lines); }
        if (v.state !== "running") {
          Object.assign(job, { state: v.state, result: v.result, ended: v.ended });
          update(); resolve(job); return;
        }
      }
      setTimeout(tick, 350);
    };
    setTimeout(tick, 200);
  });
}

function streamLines(job, lines) {
  const el = document.getElementById(`console-${job.id}`);
  if (el) {
    const stick = el.scrollHeight - el.scrollTop - el.clientHeight < 40;
    el.insertAdjacentHTML("beforeend", lines.map(consoleLine).join(""));
    if (stick) el.scrollTop = el.scrollHeight;
  }
  const last = lines[lines.length - 1];
  for (const id of ["hud-line", `last-${job.id}`]) {
    const n = document.getElementById(id);
    if (n && last) n.textContent = last.replace(/^\d\d:\d\d:\d\d \[\w+\] /, "");
  }
}

// Elapsed-time tickers: any element with data-since="<epoch seconds>".
setInterval(() => {
  const now = Date.now() / 1000;
  document.querySelectorAll("[data-since]").forEach((el) => {
    const end = Number(el.dataset.until) || now;
    const s = Math.max(0, Math.floor(end - Number(el.dataset.since)));
    el.textContent = `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
  });
}, 500);
