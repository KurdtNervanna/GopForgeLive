// dom.js — tiny, safe HTML templating + formatting helpers.

const ESC = { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" };

/** A string that is already safe HTML (won't be escaped again). */
export class Raw {
  constructor(s) { this.s = s; }
  toString() { return this.s; }
}
export const raw = (s) => new Raw(String(s ?? ""));

function esc(v) {
  if (v === null || v === undefined || v === false || v === true) return "";
  if (v instanceof Raw) return v.s;
  if (Array.isArray(v)) return v.map(esc).join("");
  return String(v).replace(/[&<>"']/g, (c) => ESC[c]);
}

/** Tagged template: interpolations are HTML-escaped unless wrapped in raw()/html``. */
export function html(strings, ...vals) {
  let out = "";
  strings.forEach((s, i) => { out += s; if (i < vals.length) out += esc(vals[i]); });
  return new Raw(out);
}

/** Conditional helper: when(cond, () => html`…`). */
export const when = (cond, fn, otherwise) => (cond ? fn() : otherwise ? otherwise() : "");

export const $ = (sel, root = document) => root.querySelector(sel);
export const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

export function fmtBytes(n) {
  if (n == null || isNaN(n)) return "—";
  if (n < 1024) return `${n} bytes`;
  const u = ["KB", "MB", "GB"]; let i = -1; let v = n;
  do { v /= 1024; i++; } while (v >= 1024 && i < u.length - 1);
  return `${v >= 10 || Number.isInteger(v) ? Math.round(v) : v.toFixed(1)} ${u[i]}`;
}
export const fmtExact = (n) => `${Number(n).toLocaleString("en-US")} bytes`;

export function fmtElapsed(sec) {
  sec = Math.max(0, Math.floor(sec));
  const m = Math.floor(sec / 60), s = sec % 60;
  return `${m}:${String(s).padStart(2, "0")}`;
}

export const shortHash = (h) => (h ? `${h.slice(0, 8)}…${h.slice(-6)}` : "—");
export const basename = (p) => String(p || "").split("/").pop();

/** Location of a file relative to the USB, for friendly display. */
export function onUsbPath(p, storage) {
  if (!p) return "";
  const wd = storage?.workdir || "";
  const rel = wd && p.startsWith(wd) ? p.slice(wd.length).replace(/^\//, "") : basename(p);
  return storage?.on_usb ? `USB › gopforge-live › ${rel.split("/").join(" › ")}` : `RAM › ${rel}`;
}

/** Colour a console line by the engine's ✓ ✗ ! » markers. */
export function consoleLine(line) {
  const t = String(line);
  let cls = "";
  if (/^\s*✓|VERIFIED|success|done\.?$/i.test(t)) cls = "l-ok";
  else if (/^\s*✗|error|fail|fatal/i.test(t)) cls = "l-err";
  else if (/^\s*!|warn/i.test(t)) cls = "l-warn";
  else if (/^\s*»/.test(t)) cls = "l-info";
  else if (/^\d\d:\d\d:\d\d \[/.test(t)) cls = "l-dim";
  return `<span class="${cls}">${esc(t)}</span>\n`;
}
