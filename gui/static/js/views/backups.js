// Backups — every firmware image saved to the USB this (and earlier) sessions.
import { html, when, fmtBytes, shortHash, fmtExact } from "../dom.js";
import { icon } from "../icons.js";
import { fileArt } from "../art.js";
import { api } from "../api.js";
import { S, actions, update, toast } from "../core.js";
import { section, callout } from "../components.js";

export const title = "Backups";
const KIND = {
  bootrom: ["Boot ROM backup", "orange"], patched: ["Patched Boot ROM", "green"], vbios: ["Graphics firmware backup", "purple"],
};

export async function enter() {
  const b = await api.get("/api/backups");
  update({ backups: b.ok ? b : { ok: false, error: b.error, files: [] } });
}

Object.assign(actions, {
  "backups-refresh": async () => { await enter(); toast("info", "Backups refreshed"); },
});

export function render() {
  const b = S.backups;
  const onUsb = S.status.storage.on_usb;
  return html`<div class="page">
    <div class="page-head" style="display:flex;align-items:flex-end;gap:16px">
      <div style="flex:1"><h1 class="t-large">Backups</h1>
        <p>Firmware saved by GopForge Live. They live on this USB drive — copy them to your computer and keep them somewhere safe.</p></div>
      <button class="btn" data-act="backups-refresh">${icon("refresh")} Refresh</button>
    </div>
    ${when(!onUsb, () => callout("warn", "Backups are in memory only", "The USB’s data partition isn’t writable, so these files disappear at shut-down."))}
    ${!b ? html`<p class="muted">Loading…</p>`
      : !b.files.length ? html`<div class="empty"><div class="e-icon">${icon("archive")}</div><h2 class="t-title2">No backups yet</h2>
          <p>Backups appear here as soon as you read a Boot ROM or a graphics card’s firmware.</p></div>`
      : section(`${b.files.length} file${b.files.length === 1 ? "" : "s"}`, html`<div class="group">
          ${b.files.map((f) => {
            const [label, tone] = KIND[f.kind] || ["Firmware", "blue"];
            return html`<div class="row tall">
              <div style="width:40px">${fileArt(f.kind)}</div>
              <div class="main-col">
                <div class="title select-text" style="word-break:break-all">${f.name}</div>
                <div class="subtitle">${label} · ${f.modified || ""} · <span class="mono" title="${f.sha256}">SHA-256 ${shortHash(f.sha256)}</span></div>
              </div>
              <span class="pill ${tone}">${fmtBytes(f.size)}</span>
            </div>`;
          })}
        </div>`, html`Folder on the USB: <span class="mono">gopforge-live/firmware/Backups</span> and <span class="mono">gopforge-live/video/Backups</span>.`)}
  </div>`;
}
