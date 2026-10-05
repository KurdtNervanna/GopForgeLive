// 4,1→5,1 Crossflash (Mac Pro 4,1 / 5,1): rebuild the Boot ROM on a clean 144.0.0.0.0
// template — a 4,1 → 5,1 crossflash, or a fresh 144.0.0.0.0 image for a 5,1.
// Template → Back Up → Build → Flash → Finish.
import { html, when, fmtExact, shortHash } from "../dom.js";
import { icon, sq, status } from "../icons.js";
import { chipArt, successArt } from "../art.js";
import { api } from "../api.js";
import { S, actions, update, runJob, openSheet, toast, jobRunning } from "../core.js";
import { section, callout, checkRow, steps, fileCard, jobBlock, locked } from "../components.js";
import { macInfo } from "../macs.js";

export const title = "4,1→5,1 Crossflash";
const STEPS = [
  { id: "template", label: "Template" }, { id: "backup", label: "Back Up" },
  { id: "build", label: "Build" }, { id: "flash", label: "Flash" }, { id: "finish", label: "Finish" },
];
const R = () => S.rb;
const fresh = () => ({ templates: R().templates, dump: null, id: null, variant: "none", image: null, report: null,
  facts: null, written: false, error: null, stale: false, locked: false });
const myJob = (...n) => (S.job && S.job.owner === "rb" && n.includes(S.job.action) ? S.job : null);
const savedDumps = () => (S.backups?.files || []).filter((f) => f.kind === "bootrom" && !/-144(-enablegop)?\.rom$/.test(f.name));
const isCross = () => R().id?.model === "MP41";
const fwName = (id) => id?.model === "MP41" ? "Mac Pro 4,1 firmware" : id?.model === "MP51" ? "Mac Pro 5,1 firmware" : "Unknown firmware";

function step() {
  const r = R();
  if (!r.templates?.found) return "template";
  if (!r.dump) return "backup";
  if (!r.image) return "build";
  if (!r.written) return "flash";
  return "finish";
}

export async function enter() {
  const [t, b] = await Promise.all([api.get("/api/templates"), api.get("/api/backups")]);
  if (t.ok) R().templates = t;
  if (b.ok) S.backups = b;
  if (R().dump && !R().id) await loadIdentity();
  update();
}

async function loadIdentity() {
  const id = await api.get(`/api/rom-identity?path=${encodeURIComponent(R().dump.path)}`);
  R().id = id.ok ? id : null;
  update();
}

// ------------------------------------------------------------------ actions --
async function doDump() {
  const job = await runJob("dump-bootrom", {}, { owner: "rb", title: "Reading the Boot ROM…" });
  if (job?.state === "done") {
    Object.assign(R(), { ...fresh(), dump: job.result.dump, locked: (job.result.protection?.protected || []).length > 0 });
    toast("ok", "Boot ROM backed up", `${job.result.dump.name} saved to the USB.`);
    await loadIdentity();
    enter();
  } else if (job) {
    toast("bad", "Couldn’t read the Boot ROM", job.result?.error || "See the details.");
  }
}

async function doBuild() {
  const r = R();
  const job = await runJob("rebuild-bootrom", { dump: r.dump.path, variant: r.variant },
    { owner: "rb", title: "Building the 144.0.0.0.0 image…" });
  if (job?.state === "done") {
    Object.assign(r, { image: job.result.image, report: job.result.report, facts: job.result.facts, error: null });
    toast("ok", "Firmware image ready", "Built and checked — nothing has been written yet.");
    enter();
  } else if (job) {
    toast("bad", "Couldn’t build the image", job.result?.error || "See the details.", 12000);
  }
  update();
}

function askFlash() {
  const r = R(); const m = S.status.machine;
  openSheet({
    kind: "confirm", tone: "danger",
    title: isCross() ? "Crossflash this Mac Pro to 5,1 firmware?" : "Write the rebuilt Boot ROM?",
    body: html`This rewrites the <strong>whole</strong> Boot ROM chip, boot block included, with
      ${isCross() ? "Mac Pro 5,1 firmware 144.0.0.0.0" : "a clean 144.0.0.0.0 image"} carrying your Mac’s serial number and MAC address.
      NVRAM starts empty. If the write is interrupted the Mac won’t start until the chip is reprogrammed with your backup.
      <strong>Don’t turn off the Mac or unplug the USB</strong> while it runs.`,
    rows: [["Target", `Boot ROM · ${m.model || "this Mac"}`], ["New image", r.image.name], ["Your backup", r.dump.name],
           ["Serial number", r.report?.result?.serial || "—"]],
    phrase: "REBUILD BOOTROM", action: isCross() ? "Crossflash" : "Write Boot ROM",
    onConfirm: async (confirm) => {
      const job = await runJob("write-rebuilt", { image: r.image.path, dump: r.dump.path },
        { owner: "rb", confirm, hud: true, title: isCross() ? "Crossflashing to 5,1" : "Writing the Boot ROM", sub: "The whole chip is written — about two minutes." });
      const code = job?.result?.code;
      if (job?.state === "done") {
        r.written = true;
        toast("ok", "Boot ROM written", "Shut down completely to finish.", 9000);
      } else if (code === "stale_backup") {
        r.stale = true; toast("warn", "Nothing was written", job.result.error, 12000);
      } else if (code === "write_protected") {
        r.locked = true; toast("warn", "Nothing was written", "The Boot ROM is write-protected — restart in flash mode first.", 12000);
      } else if (["crossflash_unverified", "not_rebuild", "read_failed", "unconfirmed", "no_template"].includes(code)) {
        toast("warn", "Nothing was written", job.result.error, 14000);
      } else if (job) {
        r.error = job.result?.error || "The write did not complete.";
        toast("bad", "Writing failed", r.error, 14000);
      }
      update();
    },
  });
}

Object.assign(actions, {
  "rb-templates": async () => { await enter(); toast(R().templates?.found ? "ok" : "warn", R().templates?.found ? "Template found" : "No template yet"); },
  "rb-dump": doDump,
  "rb-use": async (el) => {
    if (jobRunning()) return;
    const f = savedDumps().find((x) => x.path === el.dataset.path);
    if (!f) return;
    Object.assign(R(), { ...fresh(), dump: f });
    await loadIdentity();
  },
  "rb-variant": (el) => { R().variant = el.dataset.v; update(); },
  "rb-build": doBuild,
  "rb-flash": askFlash,
  "rb-redo": () => { if (jobRunning()) return; Object.assign(R(), fresh()); update(); doDump(); },
  "rb-reset": () => { if (jobRunning()) return; Object.assign(R(), fresh()); update(); },
});

// ------------------------------------------------------------------- render --
function panelHead(h, p) {
  return html`<div class="panel-head"><div style="width:84px;height:84px;flex:none">${chipArt()}</div>
    <div class="txt"><h2 class="t-title2">${h}</h2><p>${p}</p></div></div>`;
}
const flashModeSteps = () => html`<ol style="margin:8px 0 0;padding-left:4px;list-style:none">
  <li style="margin:4px 0"><strong>1.</strong> Shut down.</li>
  <li style="margin:4px 0"><strong>2.</strong> Hold the power button until the Mac beeps (the power light flashes), then let go.</li>
  <li style="margin:4px 0"><strong>3.</strong> Hold ⌥ Option and choose EFI Boot to start this USB.</li>
  <li style="margin:4px 0"><strong>4.</strong> Back up, build and write in that session — NVRAM changes on every start.</li></ol>`;

function viewTemplate() {
  const t = R().templates;
  return html`<div class="panel">
    ${panelHead("Add the 144.0.0.0.0 template", "The new firmware is built from a clean Mac Pro 5,1 Boot ROM template. It contains Apple firmware, so it isn’t included on this USB — add it once from any computer.")}
    <div class="group">
      <div class="row"><span class="sq bg-blue" style="font-weight:700;font-size:13px">1</span><div class="main-col"><div class="title">Download templates.zip</div>
        <div class="subtitle">From Borowski’s guide on MacRumors: <span class="mono select-text">${t?.url || ""}</span></div></div></div>
      <div class="row"><span class="sq bg-blue" style="font-weight:700;font-size:13px">2</span><div class="main-col"><div class="title">Copy it to the USB as-is</div>
        <div class="subtitle">Into <span class="mono">gopforge-live/templates/</span> — no need to unzip.</div></div></div>
      <div class="row"><span class="sq bg-blue" style="font-weight:700;font-size:13px">3</span><div class="main-col"><div class="title">Check again</div>
        <div class="subtitle">GopForge Live verifies the file’s SHA-256 before using it.</div></div></div>
    </div>
    <div style="margin-top:var(--s4)">${callout("info", "Only the known template is accepted",
      html`templates.zip <span class="mono">${shortHash(t?.zip_sha256 || "")}</span> or v144.0.0.0.0_template.bin <span class="mono">${shortHash(t?.bin_sha256 || "")}</span>.`)}</div>
    <div class="btn-row"><span class="grow"></span>
      <button class="btn primary large" data-act="rb-templates">${icon("refresh")} Check Again</button></div>
  </div>`;
}

function viewBackup() {
  const j = myJob("dump-bootrom");
  const saved = savedDumps();
  return html`<div class="panel">
    ${panelHead("Back up your Boot ROM", "Your Mac’s serial number, hardware code and MAC address are taken from this backup. Nothing is changed.")}
    ${callout("info", "Best done in flash mode", html`Writing the new firmware needs the chip unlocked. Start this whole flow in flash mode, so the backup and the write happen in the same session:${flashModeSteps()}`)}
    ${jobBlock(j, { running: "Reading the Boot ROM…", done: "Backup complete", failed: "The Boot ROM couldn’t be read" })}
    <div class="btn-row"><span class="grow"></span>
      <button class="btn primary large" data-act="rb-dump" ${jobRunning() ? "disabled" : ""}>${icon("download")} Back Up Boot ROM</button></div>
    ${when(saved.length, () => section("Or use a saved backup", html`<div class="group">
      ${saved.slice(0, 4).map((f) => html`<div class="row">${sq("archive", "blue")}
        <div class="main-col"><div class="title select-text" style="word-break:break-all">${f.name}</div>
          <div class="subtitle">${f.modified || ""} · <span class="mono">${shortHash(f.sha256)}</span></div></div>
        <button class="btn" data-act="rb-use" data-path="${f.path}" ${jobRunning() ? "disabled" : ""}>Use</button></div>`)}
    </div>`, "Before anything is written the chip is re-read — if it changed since this backup, you’ll be asked to back up again."))}
  </div>`;
}

function identityGroup(id) {
  const row = (ic, col, t, v) => html`<div class="row">${sq(ic, col)}<div class="main-col"><div class="title">${t}</div><div class="subtitle select-text">${v || "—"}</div></div></div>`;
  return html`<div class="group">
    ${row("chip", "orange", "Current firmware", html`${fwName(id)} · <span class="mono">${id?.bios_id || "unknown"}</span>`)}
    ${row("hash", "blue", "Serial number", id?.serial)}
    ${row("drive", "teal", "Logic board serial (LBSN)", id?.lbsn)}
    ${row("archive", "graphite", "Stored entries", id?.fsys ? `Fsys: ${id.fsys.entries.join(", ")} · Gaid: ${(id.gaid?.entries || []).join(", ") || "—"}` : "No Fsys store found")}
  </div>`;
}

function viewBuild() {
  const r = R(); const id = r.id; const j = myJob("rebuild-bootrom");
  const choice = (v, name, body) => html`
    <button class="choice ${r.variant === v ? "on" : ""}" data-act="rb-variant" data-v="${v}" ${jobRunning() ? "disabled" : ""}>
      <span class="radio"></span><span class="c-title">${name}</span><span class="c-body">${body}</span></button>`;
  const usable = id && id.fsys && id.serial && id.id_block_present;
  return html`<div class="panel">
    ${panelHead(isCross() ? "Crossflash to Mac Pro 5,1 firmware" : "Rebuild on 144.0.0.0.0",
      isCross() ? "This Mac Pro runs 4,1 firmware. The new image is Mac Pro 5,1 firmware 144.0.0.0.0 with your Mac’s own identity moved across."
                : "A fresh 144.0.0.0.0 image with your Mac’s own identity moved across and a clean NVRAM.")}
    ${fileCard(r.dump, "bootrom")}
    <div style="margin-top:var(--s5)">${id ? identityGroup(id) : html`<p class="muted">Reading the backup…</p>`}</div>
    ${when(id && !usable, () => html`<div style="margin-top:var(--s4)">${callout("danger", "This backup can’t be used",
      "It has no serial number store or no MAC/LBSN block. The rebuild needs both — the procedure doesn’t work on damaged or blank Boot ROMs.")}</div>`)}
    ${when(isCross(), () => html`<div style="margin-top:var(--s4)">${callout("warn", "4,1 crossflash: not yet verified on real hardware",
      "The steps match the community procedure, and the result is checked thoroughly before writing, but GopForge Live hasn’t crossflashed a real 4,1 yet. Writing requires Expert Mode.")}</div>`)}
    ${section("What changes", html`<div class="group checks">
      ${checkRow("info", "Firmware becomes 144.0.0.0.0", "MP51.88Z.F000.B00.1904121248 — the final Mac Pro 5,1 Boot ROM")}
      ${checkRow("ok", "Serial number, hardware code and MAC address kept", "Moved from your backup into the new image, then re-checked")}
      ${checkRow("warn", "NVRAM starts empty", "Startup disk, firmware password and other settings are cleared — choose your startup disk again afterwards")}
    </div>`)}
    ${section("Add EnableGop too?", html`<div class="choices">
      ${choice("none", "No", "Firmware update only.")}
      ${choice("standard", "Standard", "Boot screen for most GOP-capable cards.")}
      ${choice("direct", "Direct", "For cards that show signal at the chime but stay black.")}
    </div>`)}
    ${jobBlock(j, { running: "Building…", done: "Image built and checked", failed: "The image couldn’t be built" })}
    <div class="btn-row">
      <button class="btn" data-act="rb-reset" ${jobRunning() ? "disabled" : ""}>Start Over</button><span class="grow"></span>
      <button class="btn primary large" data-act="rb-build" ${!usable || jobRunning() ? "disabled" : ""}>${icon("layers")} Build Firmware Image</button>
    </div>
  </div>`;
}

function viewFlash() {
  const r = R(); const c = r.report?.checks || {}; const j = myJob("write-rebuilt");
  const needExpert = isCross() && !S.status.expert;
  const label = { fsys_crc: "Fsys store checksum valid", gaid_crc: "Gaid store checksum valid", last_volume: "Last volume checksums valid",
    serial: "Serial number carried over", hwc: "Hardware code carried over", fsys_entries: "Fsys entries identical to your backup",
    gaid_entries: "Gaid entries identical to your backup", id_block: "MAC address / LBSN block identical", rest_is_template: "Everything else is the clean template",
    bios_id: "Firmware is 144.0.0.0.0" };
  return html`<div class="panel">
    ${panelHead("Ready to write", "The image was rebuilt and re-read as if it were a fresh dump. Every check below passed.")}
    <div class="group checks">${Object.keys(label).map((k) => checkRow(c[k] ? "ok" : "bad", label[k]))}
      ${checkRow("info", "Your Boot ROM is re-read first", "Nothing is written unless the chip still matches your backup")}</div>
    ${section("What will be written", html`<div class="group">
      <div class="row">${sq("chip", "orange")}<div class="main-col"><div class="title">Target</div><div class="subtitle">Whole Boot ROM chip · ${S.status.machine.model}</div></div></div>
      <div class="row">${sq("layers", "green")}<div class="main-col"><div class="title">New image</div><div class="subtitle">${r.image.name} · <span class="mono">${shortHash(r.image.sha256)}</span></div></div></div>
      <div class="row">${sq("archive", "blue")}<div class="main-col"><div class="title">Your backup</div><div class="subtitle">${r.dump.name} · <span class="mono">${shortHash(r.dump.sha256)}</span></div></div>${status("ok")}</div>
    </div>`)}
    ${when(r.locked, () => html`<div style="margin-top:var(--s5)">${callout("warn", "Restart in flash mode to write",
      html`flashrom reports parts of the chip as read-only in this session. The whole chip — boot block included — has to be writable.${flashModeSteps()}`)}</div>`)}
    ${when(r.stale, () => html`<div style="margin-top:var(--s5)">${callout("warn", "Your Boot ROM changed since this backup",
      "Nothing was written. Take a fresh backup and build again.")}
      <div class="btn-row"><button class="btn primary" data-act="rb-redo" ${jobRunning() ? "disabled" : ""}>${icon("download")} Back Up Again</button></div></div>`)}
    ${when(needExpert, () => html`<div style="margin-top:var(--s5)">${callout("warn", "Expert Mode required for a 4,1 crossflash",
      html`Crossflashing hasn’t been verified on a real 4,1 with GopForge Live yet. Turn on Expert Mode in Settings to continue — and have a CH341A programmer and your backup ready.`)}</div>`)}
    <div style="margin-top:var(--s5)">${callout("danger", "The riskiest write this app makes",
      html`The boot block is rewritten too. If power is lost during the write the Mac won’t start, and recovery needs an SPI programmer (such as a CH341A) and the backup on this USB. See <span class="mono">docs/RECOVERY.md</span>.`)}</div>
    ${jobBlock(j, { running: "Writing…", done: "Boot ROM written and verified",
      failed: ["stale_backup", "write_protected", "crossflash_unverified", "not_rebuild", "read_failed", "unconfirmed"].includes(j?.result?.code) ? "Nothing was written" : "The write did not complete" })}
    ${when(r.error, () => html`<div style="margin-top:var(--s4)">${callout("danger", "Don’t turn off your Mac yet",
      html`${r.error} Open Activity for details, then retry — or put your original back from <strong>Backups › Restore</strong> (Expert Mode, since the whole chip differs). Keep the Mac powered on until one of them succeeds.`)}</div>`)}
    <div class="btn-row">
      <button class="btn" data-act="rb-reset" ${jobRunning() ? "disabled" : ""}>Start Over</button><span class="grow"></span>
      ${needExpert ? html`<button class="btn" data-act="sheet" data-sheet="settings">${icon("sliders")} Open Settings</button>` : ""}
      <button class="btn destructive large" data-act="rb-flash" ${jobRunning() || r.locked || r.stale || needExpert ? "disabled" : ""}>${icon("bolt")} ${isCross() ? "Crossflash…" : "Write Boot ROM…"}</button>
    </div>
  </div>`;
}

function viewFinish() {
  const tip = (n, t, d) => html`<div class="row"><span class="sq bg-blue" style="font-weight:700;font-size:13px">${n}</span>
    <div class="main-col"><div class="title">${t}</div><div class="subtitle">${d}</div></div></div>`;
  return html`<div class="panel">
    <div style="text-align:center">
      <div style="display:grid;place-items:center;margin:4px 0 14px">${successArt()}</div>
      <h2 class="t-title1">${isCross() ? "Now a Mac Pro 5,1" : "Boot ROM rebuilt"}</h2>
      <p class="muted" style="margin:8px auto 0;max-width:58ch;line-height:1.5">Boot ROM 144.0.0.0.0 with your Mac’s own serial number and MAC address.</p>
    </div>
    ${section("Next steps", html`<div class="group icons">
      ${tip(1, "Shut down completely", "Then power on. The first start after a new Boot ROM can take a little longer.")}
      ${tip(2, "Choose your startup disk", "NVRAM is empty: hold ⌥ Option and pick your system, then set it in Startup Disk settings.")}
      ${tip(3, "Check About This Mac", "It should report MacPro5,1 and Boot ROM 144.0.0.0.0.")}
      ${tip(4, "Something wrong?", "Your original Boot ROM is in Backups — restoring it needs Expert Mode, because the whole chip differs.")}
    </div>`)}
    <div class="btn-row">
      <button class="btn" data-act="go" data-to="backups">${icon("archive")} View Backups</button>
      <button class="btn" data-act="rb-reset">Start Over</button><span class="grow"></span>
      <button class="btn primary large" data-act="system" data-do="poweroff">${icon("power")} Shut Down</button>
    </div>
  </div>`;
}

export function render() {
  const m = S.status.machine;
  if (!(m.allow_bootrom || S.status.expert))
    return html`<div class="page">${locked("Firmware updates are for Mac Pro 4,1 and 5,1",
      html`This computer is ${m.model || "not an Apple Mac"}.`)}</div>`;
  const s = step();
  const body = { template: viewTemplate, backup: viewBackup, build: viewBuild, flash: viewFlash, finish: viewFinish }[s]();
  return html`<div class="page">
    <div class="page-head">
      <h1 class="t-large">4,1→5,1 Crossflash</h1>
      <p>Move a Mac Pro 4,1 to 5,1 firmware, or give a 5,1 a clean 144.0.0.0.0 Boot ROM — your serial number and MAC address carried over.</p>
    </div>
    ${steps(STEPS, s)}
    ${body}
  </div>`;
}
