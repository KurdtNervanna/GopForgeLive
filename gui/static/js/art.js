// art.js — hand-drawn SVG artwork (no Apple logos / trademarks).
import { raw } from "./dom.js";

let uid = 0;
const id = (p) => `${p}${++uid}`;

const silver = (g, dir = "h") => `
  <linearGradient id="${g}" x1="0" y1="0" x2="${dir === "h" ? 1 : 0}" y2="${dir === "h" ? 0 : 1}">
    <stop offset="0" stop-color="#c9cbd0"/><stop offset=".45" stop-color="#f3f3f5"/>
    <stop offset=".62" stop-color="#e3e4e7"/><stop offset="1" stop-color="#a9abb1"/>
  </linearGradient>`;

/** Mac Pro 2009–2012 ("cheese grater"), front view. */
export function macPro() {
  const g = id("mp"), h = id("mph"), p = id("mpp"), s = id("mps");
  return raw(`<svg viewBox="0 0 128 128" aria-hidden="true">
  <defs>${silver(g)}${silver(h, "v")}
    <pattern id="${p}" width="3.2" height="3.2" patternUnits="userSpaceOnUse">
      <circle cx="1.6" cy="1.6" r="1.02" fill="#3b3d44"/><circle cx="1.35" cy="1.3" r=".45" fill="#1b1c20"/>
    </pattern>
    <linearGradient id="${s}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#000" stop-opacity=".35"/><stop offset="1" stop-color="#000" stop-opacity="0"/></linearGradient>
  </defs>
  <ellipse cx="64" cy="122.5" rx="30" ry="2.6" fill="#000" opacity=".28"/>
  <rect x="40" y="6" width="48" height="116" rx="4" fill="url(#${g})"/>
  <rect x="40" y="6" width="48" height="116" rx="4" fill="url(#${h})" opacity=".25"/>
  <!-- handles -->
  <rect x="46" y="9" width="36" height="8" rx="2.6" fill="#26272c"/>
  <rect x="46" y="9" width="36" height="3" rx="1.5" fill="url(#${s})"/>
  <rect x="46" y="111" width="36" height="8" rx="2.6" fill="#26272c"/>
  <!-- front panel -->
  <rect x="42.5" y="20" width="43" height="88" rx="1.5" fill="#d9dadd"/>
  <rect x="42.5" y="20" width="43" height="23" rx="1.5" fill="url(#${g})"/>
  <rect x="48" y="26.5" width="32" height="1.4" rx=".7" fill="#6e7077"/>
  <rect x="48" y="33" width="32" height="1.4" rx=".7" fill="#6e7077"/>
  <circle cx="47.5" cy="39" r="1.5" fill="#7b7d84"/><circle cx="47.5" cy="39" r=".7" fill="#e9eaec"/>
  <rect x="44" y="45" width="40" height="61" rx="1.2" fill="url(#${p})"/>
  <rect x="44" y="45" width="40" height="61" rx="1.2" fill="none" stroke="#9fa1a7" stroke-width=".6"/>
  <rect x="40.5" y="6.5" width="47" height="115" rx="3.6" fill="none" stroke="#ffffff" stroke-opacity=".55" stroke-width=".8"/>
</svg>`);
}

/** Aluminium iMac 2009–2011. */
export function iMac() {
  const g = id("im"), scr = id("ims"), gl = id("img"), st = id("imt");
  return raw(`<svg viewBox="0 0 128 128" aria-hidden="true">
  <defs>${silver(g)}
    <linearGradient id="${scr}" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#1f3a8a"/><stop offset=".5" stop-color="#5b3fb8"/><stop offset="1" stop-color="#0d5f86"/>
    </linearGradient>
    <linearGradient id="${gl}" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#fff" stop-opacity=".22"/><stop offset=".42" stop-color="#fff" stop-opacity="0"/></linearGradient>
    <linearGradient id="${st}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#a9abb1"/><stop offset="1" stop-color="#e2e3e6"/></linearGradient>
  </defs>
  <ellipse cx="64" cy="121" rx="30" ry="2.4" fill="#000" opacity=".26"/>
  <path d="M52 96h24l5 22H47z" fill="url(#${st})"/>
  <rect x="42" y="116" width="44" height="4" rx="2" fill="url(#${g})"/>
  <rect x="6" y="12" width="116" height="84" rx="5" fill="url(#${g})"/>
  <rect x="6" y="12" width="116" height="70" rx="5" fill="#0c0c0e"/>
  <rect x="6" y="76" width="116" height="6" fill="#0c0c0e"/>
  <rect x="11.5" y="17.5" width="105" height="59" rx="1" fill="url(#${scr})"/>
  <circle cx="30" cy="37" r="22" fill="#8fb7ff" opacity=".22"/><circle cx="96" cy="64" r="26" fill="#58e1ff" opacity=".14"/>
  <rect x="6" y="12" width="116" height="70" rx="5" fill="url(#${gl})"/>
  <circle cx="64" cy="14.8" r=".9" fill="#2b2c30"/>
  <rect x="6.5" y="12.5" width="115" height="83" rx="4.6" fill="none" stroke="#fff" stroke-opacity=".35" stroke-width=".8"/>
</svg>`);
}

/** Generic / non-Apple computer. */
export function genericPC() {
  const g = id("pc");
  return raw(`<svg viewBox="0 0 128 128" aria-hidden="true">
  <defs><linearGradient id="${g}" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#4a4c53"/><stop offset="1" stop-color="#232429"/></linearGradient></defs>
  <ellipse cx="64" cy="121" rx="28" ry="2.4" fill="#000" opacity=".26"/>
  <rect x="40" y="10" width="48" height="110" rx="6" fill="url(#${g})"/>
  <rect x="47" y="20" width="34" height="3" rx="1.5" fill="#6d6f77"/><rect x="47" y="28" width="34" height="3" rx="1.5" fill="#6d6f77"/>
  <circle cx="64" cy="100" r="5" fill="none" stroke="#8a8c94" stroke-width="2"/><path d="M64 94.5v5" stroke="#8a8c94" stroke-width="2" stroke-linecap="round"/>
</svg>`);
}

export function macArt(model = "") {
  if (/^MacPro/i.test(model)) return macPro();
  if (/^iMac/i.test(model)) return iMac();
  return genericPC();
}

/** App icon — a firmware chip with a glowing boot-screen core. */
export function appIcon() {
  const bg = id("ai"), chip = id("aic"), core = id("aio"), glow = id("aig");
  return raw(`<svg class="app-icon" viewBox="0 0 100 100" aria-hidden="true">
  <defs>
    <linearGradient id="${bg}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#43464f"/><stop offset="1" stop-color="#16171c"/></linearGradient>
    <linearGradient id="${chip}" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#f4f4f6"/><stop offset=".55" stop-color="#c8cad0"/><stop offset="1" stop-color="#9c9ea5"/></linearGradient>
    <linearGradient id="${core}" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#3d8bff"/><stop offset="1" stop-color="#8a4dff"/></linearGradient>
    <radialGradient id="${glow}" cx=".5" cy=".5" r=".5"><stop offset="0" stop-color="#5aa0ff" stop-opacity=".55"/><stop offset="1" stop-color="#5aa0ff" stop-opacity="0"/></radialGradient>
  </defs>
  <rect x="4" y="4" width="92" height="92" rx="21" fill="url(#${bg})"/>
  <rect x="4.5" y="4.5" width="91" height="91" rx="20.5" fill="none" stroke="#fff" stroke-opacity=".14"/>
  <circle cx="50" cy="50" r="34" fill="url(#${glow})"/>
  <g fill="#aeb0b6">${[34, 42, 50, 58, 66].map((v) =>
    `<rect x="${v - 2}" y="18" width="4" height="8" rx="1.2"/><rect x="${v - 2}" y="74" width="4" height="8" rx="1.2"/><rect x="18" y="${v - 2}" width="8" height="4" rx="1.2"/><rect x="74" y="${v - 2}" width="8" height="4" rx="1.2"/>`).join("")}</g>
  <rect x="25" y="25" width="50" height="50" rx="9" fill="url(#${chip})"/>
  <rect x="33" y="33" width="34" height="34" rx="6" fill="url(#${core})"/>
  <path d="M52.5 38 41.5 52.5h8L47.5 62 58.5 47.5h-8z" fill="#fff"/>
</svg>`);
}

/** SPI flash chip (the Boot ROM), SOIC-8. */
export function chipArt() {
  const b = id("ch"), l = id("chl");
  return raw(`<svg viewBox="0 0 128 128" aria-hidden="true">
  <defs>
    <linearGradient id="${b}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#3a3b41"/><stop offset="1" stop-color="#141519"/></linearGradient>
    <linearGradient id="${l}" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#9fa2a8"/><stop offset=".5" stop-color="#f1f1f3"/><stop offset="1" stop-color="#9fa2a8"/></linearGradient>
  </defs>
  <ellipse cx="64" cy="104" rx="42" ry="4" fill="#000" opacity=".25"/>
  ${[0, 1, 2, 3].map((i) => `<rect x="${31 + i * 19}" y="24" width="9" height="14" rx="1.5" fill="url(#${l})"/><rect x="${31 + i * 19}" y="88" width="9" height="14" rx="1.5" fill="url(#${l})"/>`).join("")}
  <rect x="20" y="34" width="88" height="58" rx="6" fill="url(#${b})"/>
  <rect x="20.5" y="34.5" width="87" height="57" rx="5.5" fill="none" stroke="#fff" stroke-opacity=".12"/>
  <circle cx="31" cy="45" r="3.2" fill="#0b0b0d"/><circle cx="31" cy="45" r="3.2" fill="none" stroke="#fff" stroke-opacity=".1"/>
  <text x="64" y="66" text-anchor="middle" font-family="JetBrains Mono, monospace" font-size="8.5" font-weight="600" fill="#c8c9ce" opacity=".9">BOOT ROM</text>
  <text x="64" y="78" text-anchor="middle" font-family="JetBrains Mono, monospace" font-size="6" fill="#8d8f96">SPI · 32 Mbit</text>
</svg>`);
}

/** Graphics card. */
export function gpuArt() {
  const s = id("gs"), f = id("gf"), br = id("gb");
  return raw(`<svg viewBox="0 0 128 128" aria-hidden="true">
  <defs>
    <linearGradient id="${s}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#46474e"/><stop offset="1" stop-color="#1a1b20"/></linearGradient>
    <radialGradient id="${f}" cx=".5" cy=".5" r=".5"><stop offset="0" stop-color="#2d2e34"/><stop offset=".7" stop-color="#101114"/><stop offset="1" stop-color="#3a3b42"/></radialGradient>
    <linearGradient id="${br}" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#b9bbc1"/><stop offset=".5" stop-color="#f2f2f4"/><stop offset="1" stop-color="#a3a5ab"/></linearGradient>
  </defs>
  <ellipse cx="66" cy="106" rx="48" ry="4" fill="#000" opacity=".25"/>
  <rect x="12" y="30" width="7" height="68" rx="1.5" fill="url(#${br})"/>
  <rect x="19" y="34" width="98" height="56" rx="6" fill="url(#${s})"/>
  <rect x="19.5" y="34.5" width="97" height="55" rx="5.5" fill="none" stroke="#fff" stroke-opacity=".14"/>
  <circle cx="54" cy="62" r="20" fill="url(#${f})"/>
  ${Array.from({ length: 9 }, (_, i) => `<path d="M54 62 L54 44 A18 18 0 0 1 63 46.4 Z" fill="#5a5b63" opacity=".55" transform="rotate(${i * 40} 54 62)"/>`).join("")}
  <circle cx="54" cy="62" r="5" fill="#26272c" stroke="#6b6d74" stroke-width="1"/>
  <rect x="82" y="46" width="26" height="4" rx="2" fill="#0a84ff" opacity=".85"/>
  <rect x="82" y="54" width="18" height="3" rx="1.5" fill="#6d6f77"/>
  <rect x="44" y="90" width="52" height="7" rx="1" fill="#d4a531"/>
  ${Array.from({ length: 12 }, (_, i) => `<rect x="${46 + i * 4.1}" y="91" width="2" height="5" fill="#b8891d"/>`).join("")}
</svg>`);
}

/** Document icon with a coloured band. kind: bootrom | patched | vbios | rom */
export function fileArt(kind = "rom") {
  const colors = { bootrom: "#ff9f0a", patched: "#30d158", vbios: "#bf5af2", rom: "#0a84ff" };
  const label = { bootrom: "ROM", patched: "GOP", vbios: "BIOS", rom: "ROM" }[kind] || "ROM";
  const g = id("fa");
  return raw(`<svg class="fc-icon" viewBox="0 0 40 48" aria-hidden="true">
  <defs><linearGradient id="${g}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffffff"/><stop offset="1" stop-color="#e3e4e8"/></linearGradient></defs>
  <path d="M5 2h21l10 10v32a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2z" fill="url(#${g})" stroke="#000" stroke-opacity=".12"/>
  <path d="M26 2v8a2 2 0 0 0 2 2h8" fill="#d4d5da"/>
  <rect x="3" y="28" width="33" height="11" fill="${colors[kind] || colors.rom}"/>
  <text x="19.5" y="36.4" text-anchor="middle" font-family="Inter Var, sans-serif" font-size="7.5" font-weight="800" fill="#fff" letter-spacing=".4">${label}</text>
</svg>`);
}

/** Big success glyph for finish screens. */
export function successArt() {
  const g = id("ok");
  return raw(`<svg viewBox="0 0 96 96" aria-hidden="true" style="width:88px;height:88px">
  <defs><linearGradient id="${g}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#4cdc72"/><stop offset="1" stop-color="#1fae4b"/></linearGradient></defs>
  <circle cx="48" cy="48" r="44" fill="#30d158" opacity=".16"/>
  <circle cx="48" cy="48" r="34" fill="url(#${g})"/>
  <path d="m33 49 10 10 20-22" fill="none" stroke="#fff" stroke-width="6" stroke-linecap="round" stroke-linejoin="round"/>
</svg>`);
}

/** Big caution glyph for destructive sheets. */
export function cautionArt(color = "#ff9f0a") {
  return raw(`<svg class="s-icon" viewBox="0 0 56 56" aria-hidden="true">
  <path d="M24.5 7.6 4.6 42.2A4 4 0 0 0 8.1 48h39.8a4 4 0 0 0 3.5-5.8L31.5 7.6a4 4 0 0 0-7 0z" fill="${color}"/>
  <path d="M28 21v12" stroke="#fff" stroke-width="4.2" stroke-linecap="round"/><circle cx="28" cy="40" r="2.6" fill="#fff"/>
</svg>`);
}
