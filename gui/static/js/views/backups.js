// Backups — every firmware image saved to the USB this (and earlier) sessions,
// with Restore for original Boot ROM and graphics-firmware backups.
import { html, when, fmtBytes, shortHash } from "../dom.js";
import { icon } from "../icons.js";
import { fileArt } from "../art.js";
import { api } from "../api.js";
import { S, actions, update, toast, openSheet, runJob, jobRunning } from "../core.js";
import { section, callout, jobBlock } from "../components.js";
import { macInfo } from "../macs.js";

export const title = "Backups";
const KIND = {
  bootrom: ["Boot ROM backup", "orange"], patched: ["Patched Boot ROM", "green"], vbios: ["Graphics firmware backup", "purple"],
};

export async function enter() {
  const b = await api.get("/api/backups");
  update({ backups: b.ok ? b : { ok: false, error: b.error, files: [] } });
}

// amd-adapter0-….rom / nvidia-idx1-….rom → which card it came from
function gpuOf(name) {
  let m = /^amd-adapter(\d+)-/.exec(name);
  if (m) return { vendor: "amd", index: m[1], label: `AMD adapter ${m[1]}` };
  m = /^nvidia-idx(\d+)-/.exec(name);
  if (m) return { vendor: "nvidia", index: m[1], label: `NVIDIA card ${m[1]}` };
  return null;
}

function canRestore(f) {
  const m = S.status.machine, ex = S.status.expert;
  if (f.kind === "bootrom") return m.allow_bootrom || ex;
  if (f.kind === "vbios") return (m.allow_gpu || ex) && !!gpuOf(f.name);
  return false;
}

const myJob = () => (S.job && S.job.owner === "backups" ? S.job : null);

function askRestore(f) {
  const m = S.status.machine;
  const rom = f.kind === "bootrom";
  const g = rom ? null : gpuOf(f.name);
  openSheet({
    kind: "confirm", tone: "danger",
    title: rom ? "Restore this Boot ROM backup?" : "Restore this graphics firmware?",
    body: rom
      ? html`This writes the backup back to your ${macInfo(m.model).name}’s Boot ROM, undoing any patch made since it was taken.
          Normally it’s only allowed when the chip is this backup plus changes to its DXE drivers — an older or foreign backup needs Expert Mode.
          <strong>Don’t turn off the Mac</strong> while it runs.`
      : html`This flashes the saved firmware back onto ${g.label}. <strong>Don’t turn off the Mac</strong> while it runs.`,
    rows: [["Target", rom ? `Boot ROM · ${m.model || "this Mac"}` : g.label], ["Backup", f.name], ["SHA-256", shortHash(f.sha256)]],
    phrase: rom ? "RESTORE BOOTROM" : "RESTORE", action: "Restore",
    onConfirm: async (confirm) => {
      const job = rom
        ? await runJob("restore-bootrom", { backup: f.path },
            { owner: "backups", confirm, hud: true, title: "Restoring the Boot ROM", sub: "The chip is read, checked and rewritten — about two minutes." })
        : await runJob("restore-gpu", { vendor: g.vendor, index: g.index, backup: f.path },
            { owner: "backups", confirm, hud: true, title: "Restoring graphics firmware", sub: "This takes about a minute." });
      if (job?.state === "done") {
        toast("ok", job.result.unchanged ? "Already restored" : "Backup restored",
          job.result.unchanged ? "The chip already matches this backup — nothing was written." : "Shut down completely to finish.", 9000);
      } else if (job) {
        toast(job.result?.code === "not_this_state" ? "warn" : "bad", "Restore didn’t run", job.result?.error || "See Activity.", 14000);
      }
      update();
    },
  });
}

Object.assign(actions, {
  "backups-refresh": async () => { await enter(); toast("info", "Backups refreshed"); },
  "backups-restore": (el) => {
    if (jobRunning()) return;
    const f = (S.backups?.files || []).find((x) => x.path === el.dataset.path);
    if (f) askRestore(f);
  },
});

export function render() {
  const b = S.backups;
  const onUsb = S.status.storage.on_usb;
  const j = myJob();
  return html`<div class="page">
    <div class="page-head" style="display:flex;align-items:flex-end;gap:16px">
      <div style="flex:1"><h1 class="t-large">Backups</h1>
        <p>Firmware saved by GopForge Live. They live on this USB drive — copy them to your computer and keep them somewhere safe.</p></div>
      <button class="btn" data-act="backups-refresh">${icon("refresh")} Refresh</button>
    </div>
    ${when(!onUsb, () => callout("warn", "Backups are in memory only", "The USB’s data partition isn’t writable, so these files disappear at shut-down."))}
    ${jobBlock(j, { running: "Restoring…", done: "Restore finished", failed: "Restore didn’t run" })}
    ${!b ? html`<p class="muted">Loading…</p>`
      : !b.files.length ? html`<div class="empty"><div class="e-icon">${icon("archive")}</div><h2 class="t-title2">No backups yet</h2>
          <p>Backups appear here as soon as you read a Boot ROM or a graphics card’s firmware.</p></div>`
      : section(`${b.files.length} file${b.files.length === 1 ? "" : "s"}`, html`<div class="group">
          ${b.files.map((f) => {
            const [label, tone] = KIND[f.kind] || ["Firmware", "blue"];
            const g = f.kind === "vbios" ? gpuOf(f.name) : null;
            return html`<div class="row tall">
              <div style="width:40px">${fileArt(f.kind)}</div>
              <div class="main-col">
                <div class="title select-text" style="word-break:break-all">${f.name}</div>
                <div class="subtitle">${label}${g ? ` · ${g.label}` : ""} · ${f.modified || ""} · <span class="mono" title="${f.sha256}">SHA-256 ${shortHash(f.sha256)}</span></div>
              </div>
              <span class="pill ${tone}">${fmtBytes(f.size)}</span>
              ${when(canRestore(f), () => html`<button class="btn" data-act="backups-restore" data-path="${f.path}" ${jobRunning() ? "disabled" : ""}>${icon("refresh")} Restore…</button>`)}
            </div>`;
          })}
        </div>`, html`Folder on the USB: <span class="mono">gopforge-live/firmware/Backups</span> and <span class="mono">gopforge-live/video/Backups</span>.`)}
  </div>`;
}
