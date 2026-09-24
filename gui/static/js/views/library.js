// ROM Library — the full IMAC-EFI-BOOT-SCREEN firmware set bundled on the disk.
import { html, when, fmtBytes } from "../dom.js";
import { icon } from "../icons.js";
import { api } from "../api.js";
import { S, actions, update } from "../core.js";
import { section, methodBadge } from "../components.js";
import { method, romTitle } from "../macs.js";

export const title = "ROM Library";
const ORDER = ["gop", "eg2", "eg", "eg91", "uga", "lvds", "orig", "apple"];

export async function enter() {
  if (!S.library) {
    const l = await api.get("/api/library");
    update({ library: l.ok ? l.roms : [] });
  }
}

Object.assign(actions, {
  "lib-method": (el) => { S.libFilter.method = el.dataset.m; update(); },
});

export function onInput(el) {
  if (el.id === "lib-q") {
    S.libFilter.q = el.value;
    update();
    return true;
  }
  return false;
}

export function render() {
  const all = S.library;
  const f = S.libFilter;
  const q = f.q.trim().toLowerCase();
  const list = (all || []).filter((r) => (f.method === "all" || r.method === f.method) && (!q || r.file.toLowerCase().includes(q)));
  const methods = ORDER.filter((m) => (all || []).some((r) => r.method === m));
  const groups = ORDER.map((m) => [m, list.filter((r) => r.method === m)]).filter(([, l]) => l.length);
  return html`<div class="page">
    <div class="page-head"><h1 class="t-large">ROM Library</h1>
      <p>${all ? all.length : "…"} GOP-enabled graphics firmware images for iMac MXM cards, from the IMAC-EFI-BOOT-SCREEN project (GPL-3.0). The Graphics Card page picks from these for you.</p></div>
    <div style="display:flex;gap:12px;align-items:center;flex-wrap:wrap;margin-bottom:var(--s5)">
      <div class="search" style="flex:1;min-width:240px">${icon("search")}<input id="lib-q" data-input="lib" placeholder="Search by card, e.g. WX4150" value="${f.q}" autocomplete="off" spellcheck="false"></div>
      <div class="segmented">
        <button class="${f.method === "all" ? "on" : ""}" data-act="lib-method" data-m="all">All</button>
        ${methods.map((m) => html`<button class="${f.method === m ? "on" : ""}" data-act="lib-method" data-m="${m}">${method(m).label}</button>`)}
      </div>
    </div>
    ${!all ? html`<p class="muted">Loading…</p>` : !groups.length ? html`<div class="empty"><div class="e-icon">${icon("search")}</div><h2 class="t-title2">No matches</h2><p>Try a different card name.</p></div>`
      : groups.map(([m, l]) => section(`${method(m).name} · ${l.length}`, html`<div class="group">${l.map((r) => html`
          <div class="row">${methodBadge(m)}
            <div class="main-col"><div class="title">${romTitle(r.file)}</div><div class="subtitle mono">${r.file}</div></div>
            <span class="value">${fmtBytes(r.size)}</span>
          </div>`)}</div>`, method(m).blurb))}
  </div>`;
}
