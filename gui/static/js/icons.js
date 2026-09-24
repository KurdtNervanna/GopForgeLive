// icons.js — one line-icon family, one stroke weight (1.75), rounded caps,
// sized with the text it sits next to (Apple: "icon and type are one system").
// Glyph geometry follows the Lucide set (ISC licence) where noted.
import { raw } from "./dom.js";

const P = {
  chevronRight: `<path d="m9 18 6-6-6-6"/>`,
  chevronLeft: `<path d="m15 18-6-6 6-6"/>`,
  chevronDown: `<path d="m6 9 6 6 6-6"/>`,
  check: `<path d="M20 6 9 17l-5-5"/>`,
  x: `<path d="M18 6 6 18M6 6l12 12"/>`,
  info: `<circle cx="12" cy="12" r="10"/><path d="M12 16v-4M12 8h.01"/>`,
  alert: `<path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z"/><path d="M12 9v4M12 17h.01"/>`,
  chip: `<rect x="5" y="5" width="14" height="14" rx="2"/><rect x="9" y="9" width="6" height="6" rx="1"/><path d="M9 2v3M15 2v3M9 19v3M15 19v3M2 9h3M2 15h3M19 9h3M19 15h3"/>`,
  gpu: `<path d="M3 7h16a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2H3"/><path d="M3 5v15"/><circle cx="10" cy="12.5" r="3"/><path d="M16 11v3M7 18v2M11 18v2M15 18v2"/>`,
  monitor: `<rect x="2" y="3" width="20" height="14" rx="2"/><path d="M8 21h8M12 17v4"/>`,
  archive: `<rect x="2" y="3" width="20" height="5" rx="1"/><path d="M4 8v11a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8M10 12h4"/>`,
  layers: `<path d="m12 2 10 5-10 5L2 7l10-5Z"/><path d="m2 17 10 5 10-5M2 12l10 5 10-5"/>`,
  terminal: `<path d="m4 17 6-6-6-6M12 19h8"/>`,
  sliders: `<path d="M21 4h-7M10 4H3M21 12h-9M8 12H3M21 20h-5M12 20H3M14 2v4M8 10v4M16 18v4"/>`,
  power: `<path d="M12 2v10"/><path d="M18.4 6.6a9 9 0 1 1-12.77.04"/>`,
  restart: `<path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"/><path d="M3 3v5h5"/>`,
  refresh: `<path d="M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8"/><path d="M21 3v5h-5"/><path d="M21 12a9 9 0 0 1-9 9 9.75 9.75 0 0 1-6.74-2.74L3 16"/><path d="M8 16H3v5"/>`,
  download: `<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><path d="m7 10 5 5 5-5M12 15V3"/>`,
  bolt: `<path d="M13 2 3 14h9l-1 8 10-12h-9l1-8z"/>`,
  shield: `<path d="M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z"/>`,
  shieldCheck: `<path d="M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z"/><path d="m9 12 2 2 4-4"/>`,
  lock: `<rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/>`,
  drive: `<path d="M22 12H2"/><path d="M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"/><path d="M6 16h.01M10 16h.01"/>`,
  usb: `<rect x="7" y="9" width="10" height="13" rx="2"/><path d="M9 9V3h6v6M11 5v1M13 5v1"/>`,
  file: `<path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"/><path d="M14 2v4a2 2 0 0 0 2 2h4"/>`,
  search: `<circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/>`,
  sun: `<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2m-7.07-2.93 1.41-1.41m11.32-11.32 1.41-1.41M2 12h2m16 0h2M4.93 4.93l1.41 1.41m11.32 11.32 1.41 1.41"/>`,
  moon: `<path d="M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z"/>`,
  wrench: `<path d="M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76z"/>`,
  clock: `<circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/>`,
  hash: `<path d="M4 9h16M4 15h16M10 3 8 21M16 3l-2 18"/>`,
  copy: `<rect x="8" y="8" width="14" height="14" rx="2"/><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/>`,
  more: `<circle cx="5" cy="12" r="1.2"/><circle cx="12" cy="12" r="1.2"/><circle cx="19" cy="12" r="1.2"/>`,
  keyboard: `<rect x="2" y="5" width="20" height="14" rx="2"/><path d="M6 9h.01M10 9h.01M14 9h.01M18 9h.01M6 13h.01M18 13h.01M9 16h6"/>`,
  arrowRight: `<path d="M5 12h14M12 5l7 7-7 7"/>`,
  sparkle: `<path d="M12 3v3M12 18v3M3 12h3M18 12h3M6.3 6.3l2.1 2.1M15.6 15.6l2.1 2.1M6.3 17.7l2.1-2.1M15.6 8.4l2.1-2.1"/>`,
  macpro: `<rect x="6" y="2" width="12" height="20" rx="2"/><path d="M6 6h12M6 18h12M9 10h.01M12 10h.01M15 10h.01M9 13h.01M12 13h.01M15 13h.01"/>`,
  imac: `<rect x="2" y="3" width="20" height="13" rx="2"/><path d="M2 13h20M9 21h6M12 16v5"/>`,
  eye: `<path d="M2.06 12.35a1 1 0 0 1 0-.7 10.75 10.75 0 0 1 19.88 0 1 1 0 0 1 0 .7 10.75 10.75 0 0 1-19.88 0"/><circle cx="12" cy="12" r="3"/>`,
};

// Filled status glyphs (SF "…circle.fill" style).
const FILLED = {
  ok: `<circle cx="12" cy="12" r="10" fill="currentColor" stroke="none"/><path d="m7.5 12.3 3 3 6-6.3" stroke="#fff" stroke-width="2.2"/>`,
  bad: `<circle cx="12" cy="12" r="10" fill="currentColor" stroke="none"/><path d="m8.5 8.5 7 7m0-7-7 7" stroke="#fff" stroke-width="2.2"/>`,
  warn: `<path d="M10.3 3.6 2.2 18a2 2 0 0 0 1.7 3h16.2a2 2 0 0 0 1.7-3L13.7 3.6a2 2 0 0 0-3.4 0Z" fill="currentColor" stroke="none"/><path d="M12 9v4.2M12 17.2h.01" stroke="#fff" stroke-width="2.2"/>`,
  info: `<circle cx="12" cy="12" r="10" fill="currentColor" stroke="none"/><path d="M12 11v5.5M12 7.6h.01" stroke="#fff" stroke-width="2.2"/>`,
  dot: `<circle cx="12" cy="12" r="4.5" fill="currentColor" stroke="none"/>`,
};

export function icon(name, cls = "") {
  const body = P[name] || FILLED[name] || P.info;
  return raw(`<svg class="i ${cls}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${body}</svg>`);
}

/** Filled status glyph: level = ok | warn | bad | info */
export const status = (level) => icon(level in FILLED ? level : "info", `st ${level}`);

/** macOS-style spinner. */
export const spinner = () => raw(`<svg class="spinner" viewBox="0 0 24 24" aria-hidden="true">${
  Array.from({ length: 8 }, (_, i) => `<line x1="12" y1="3" x2="12" y2="7" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" opacity="${(0.25 + (i / 8) * 0.75).toFixed(2)}" transform="rotate(${i * 45} 12 12)"/>`).join("")
}</svg>`);

/** System-Settings style coloured rounded-square icon. */
export const sq = (name, color = "blue", size = "") => raw(`<span class="sq bg-${color} ${size}">${icon(name)}</span>`);
