// Boot ROM flow (Mac Pro 4,1 / 5,1): Back Up → Inspect → Patch → Flash → Finish.
import { html, when, fmtExact, shortHash } from "../dom.js";
import { icon, sq, status } from "../icons.js";
import { chipArt, successArt } from "../art.js";
import { S, actions, update, runJob, openSheet, toast, jobRunning, refreshStatus } from "../core.js";
import { section, callout, checkRow, steps, fileCard, jobBlock, locked } from "../components.js";
import { macInfo } from "../macs.js";

export const title = "Boot ROM";
const STEPS = [
  { id: "backup", label: "Back Up" }, { id: "inspect", label: "Inspect" },
  { id: "patch", label: "Patch" }, { id: "flash", label: "Flash" }, { id: "finish", label: "Finish" },
];

function step() {
  const b = S.br;
  if (!b.dump) return "backup";
  if (!b.checked) return "inspect";
  if (b.facts?.enablegop_present) return "already";
  if (!b.patched) return "patch";
  if (!b.written) return "flash";
  return "finish";
}
const myJob = (...names) => (S.job && S.job.owner === "br" && names.includes(S.job.action) ? S.job : null);
const validDump = (f) => f && f.is_4mib && f.firmware_volume && f.cmp_fingerprint;

// ------------------------------------------------------------------ actions --
async function doDump() {
  S.br.error = null;
  const job = await runJob("dump-bootrom", {}, { owner: "br", title: "Reading the Boot ROM…" });
  if (job?.state === "done") {
    Object.assign(S.br, { dump: job.result.dump, facts: job.result.facts });
    toast("ok", "Boot ROM backed up", `${job.result.dump.name} saved to the USB.`);
    update();
    doCheck();
  } else if (job) {
    toast("bad", "Couldn’t read the Boot ROM", job.result?.error || "See the details.");
  }
}

async function doCheck() {
  const job = await runJob("check-bootrom", { dump: S.br.dump.path }, { owner: "br", title: "Inspecting the image…" });
  if (job?.state === "done") Object.assign(S.br, { facts: job.result.facts, report: job.result.report, checked: true });
  update();
}

async function doPatch() {
  const job = await runJob("inject-bootrom", { dump: S.br.dump.path, variant: S.br.variant },
    { owner: "br", title: `Adding EnableGop (${S.br.variant === "direct" ? "Direct" : "Standard"})…` });
  if (job?.state === "done") {
    Object.assign(S.br, { patched: job.result.patched, pfacts: job.result.facts });
    toast("ok", "Patched image ready", "Validated and saved next to your backup.");
  } else if (job) {
    toast("bad", "Couldn’t patch the image", job.result?.error || "See the details.");
  }
  update();
}

function askFlash() {
  const b = S.br;
  const m = S.status.machine;
  openSheet({
    kind: "confirm", tone: "danger",
    title: "Flash the Boot ROM?",
    body: html`This replaces your ${macInfo(m.model).name}’s firmware with the patched image. If the write is
      interrupted, the Mac may not start until the chip is reprogrammed with your backup.
      <strong>Don’t turn off the Mac or unplug the USB</strong> while it runs.`,
    rows: [["Target", `Boot ROM · ${m.model || "this Mac"}`], ["New image", b.patched.name],
           ["Your backup", b.dump.name]],
    phrase: "FLASH BOOTROM", action: "Flash Boot ROM",
    onConfirm: async (confirm) => {
      const job = await runJob("write-bootrom", { patched: b.patched.path, dump: b.dump.path },
        { owner: "br", confirm, hud: true, title: "Writing the Boot ROM", sub: "This takes about a minute." });
      if (job?.state === "done") {
        S.br.written = true;
        toast("ok", "Boot ROM updated", "EnableGop is installed. Shut down to finish.", 9000);
      } else if (job) {
        S.br.error = job.result?.error || "The write did not complete.";
        toast("bad", "Flashing failed", S.br.error, 12000);
      }
      update();
    },
  });
}

Object.assign(actions, {
  "br-dump": doDump,
  "br-check": doCheck,
  "br-variant": (el) => { S.br.variant = el.dataset.v; update(); },
  "br-patch": doPatch,
  "br-flash": askFlash,
  "br-reset": () => {
    if (jobRunning()) return;
    S.br = { dump: null, facts: null, report: "", checked: false, variant: "standard", patched: null, pfacts: null, written: false, error: null };
    update();
  },
  "br-refresh": async () => { await refreshStatus(); toast("info", "Status refreshed"); },
});

// ------------------------------------------------------------------- render --
function panelHead(art, h, p) {
  return html`<div class="panel-head"><div style="width:84px;height:84px;flex:none">${art}</div>
    <div class="txt"><h2 class="t-title2">${h}</h2><p>${p}</p></div></div>`;
}

function factsChecks(f) {
  const eg = f.enablegop_count;
  return html`<div class="group checks">
    ${checkRow(f.is_4mib ? "ok" : "bad", "Complete 4 MB image", fmtExact(f.size))}
    ${checkRow(f.firmware_volume ? "ok" : "bad", "UEFI firmware volume found")}
    ${checkRow(f.cmp_fingerprint ? "ok" : "bad", "Mac Pro 4,1 / 5,1 Boot ROM", "EnableGop insertion point present")}
    ${checkRow(eg === 0 ? "ok" : eg === 1 ? "info" : "bad",
      eg === 0 ? "EnableGop not installed yet" : eg === 1 ? "EnableGop is already installed" : `EnableGop installed ${eg} times`,
      eg > 1 ? "A known fault state — start again from a clean dump" : "")}
  </div>`;
}

function reportDisclosure() {
  if (!S.br.report) return "";
  const open = !!S.ui.console.brReport;
  return html`<button class="disclose ${open ? "open" : ""}" data-act="toggle-console" data-id="brReport">${icon("chevronRight")} ${open ? "Hide" : "Show"} GopForge Report</button>
    <div class="console" ${open ? "" : "hidden"}>${S.br.report}</div>`;
}

function viewBackup() {
  const j = myJob("dump-bootrom");
  const usb = S.status.storage.on_usb;
  return html`<div class="panel">
    ${panelHead(chipArt(), "Back up your Boot ROM",
      "GopForge Live first reads the complete Boot ROM chip and saves the copy to this USB drive. Nothing is changed. Keep this file — it’s your way back.")}
    <div class="group">
      <div class="row">${sq("chip", "orange")}<div class="main-col"><div class="title">Source</div><div class="subtitle">SPI flash chip, read in place with flashrom</div></div></div>
      <div class="row">${sq("usb", usb ? "blue" : "gray")}<div class="main-col"><div class="title">Saved to</div><div class="subtitle">${usb ? "USB › gopforge-live › firmware › Backups" : "Memory only — will be lost at shut-down"}</div></div>${status(usb ? "ok" : "warn")}</div>
    </div>
    ${when(!usb, () => callout("warn", "Backups can’t be kept", "The USB’s data partition isn’t writable. You can still read the chip, but don’t flash anything."))}
    ${jobBlock(j, { running: "Reading the Boot ROM…", done: "Backup complete", failed: "The Boot ROM couldn’t be read" })}
    ${when(j && j.state !== "running" && j.state !== "done", () => callout("info", "If this keeps failing",
      html`flashrom needs direct hardware access. This disk boots with <span class="mono">iomem=relaxed</span> for that; if you booted a different entry, restart and pick the default one.`))}
    <div class="btn-row">
      <button class="btn primary large" data-act="br-dump" ${jobRunning() ? "disabled" : ""}>${icon("download")} ${j && j.state !== "done" ? "Try Again" : "Back Up Boot ROM"}</button>
    </div>
  </div>`;
}

function viewInspect() {
  const j = myJob("check-bootrom");
  return html`<div class="panel">
    ${panelHead(chipArt(), "Inspecting your backup", "Checking that this is a genuine Mac Pro 4,1 / 5,1 Boot ROM before anything else happens.")}
    ${fileCard(S.br.dump, "bootrom")}
    <div style="margin-top:var(--s5)">${S.br.facts ? factsChecks(S.br.facts) : ""}</div>
    ${jobBlock(j, { running: "Inspecting…", done: "Inspection complete", failed: "Inspection failed" })}
    <div class="btn-row"><button class="btn" data-act="br-check" ${jobRunning() ? "disabled" : ""}>${icon("refresh")} Inspect Again</button></div>
  </div>`;
}

function viewAlready() {
  return html`<div class="panel" style="text-align:center">
    <div style="display:grid;place-items:center;margin:8px 0 16px">${successArt()}</div>
    <h2 class="t-title2">EnableGop is already installed</h2>
    <p class="muted" style="max-width:56ch;margin:10px auto 0;line-height:1.5">This Boot ROM already contains EnableGop, so there’s nothing to patch. Adding it again would create a duplicate.
      If you still see no boot screen, your graphics card may need GOP in its own firmware as well.</p>
    <div style="margin-top:var(--s6);text-align:left">${factsChecks(S.br.facts)}${reportDisclosure()}</div>
    <div class="btn-row" style="justify-content:center"><button class="btn" data-act="br-reset">Start Over</button></div>
  </div>`;
}

function viewPatch() {
  const f = S.br.facts;
  const ok = validDump(f);
  const inj = S.status.tools.injector;
  const blocked = !(inj === "ok" || inj === "mock");
  const j = myJob("inject-bootrom");
  const expert = S.status.expert;
  const choice = (v, name, rec, body) => html`
    <button class="choice ${S.br.variant === v ? "on" : ""}" data-act="br-variant" data-v="${v}" ${jobRunning() ? "disabled" : ""}>
      <span class="radio"></span>
      <span class="c-title">${name} ${when(rec, () => html`<span class="pill blue">Recommended</span>`)}</span>
      <span class="c-body">${body}</span>
    </button>`;
  return html`<div class="panel">
    ${panelHead(chipArt(), "Add EnableGop", "GopForge inserts the EnableGop driver into a copy of your backup and validates the result. Your original file is never modified.")}
    ${fileCard(S.br.dump, "bootrom")}
    <div style="margin-top:var(--s5)">${factsChecks(f)}${reportDisclosure()}</div>
    ${when(!ok, () => html`<div style="margin-top:var(--s4)">${callout("danger", "This isn’t a Mac Pro 4,1 / 5,1 Boot ROM",
      expert ? "Expert Mode is on, so you can continue — but EnableGop only works in genuine 4,1/5,1 firmware." : "Nothing will be patched. Check that you booted the right Mac, then back up again.")}</div>`)}
    ${section("Choose a variant", html`<div class="choices">
      ${choice("standard", "Standard", true, "For most graphics cards with GOP in their firmware — RX 500, Vega, Navi and more.")}
      ${choice("direct", "Direct", false, "For cards that need direct rendering. Try this if Standard gives signal at the chime but a black screen.")}
    </div>`)}
    ${when(blocked, () => html`<div style="margin-top:var(--s5)">${callout("warn", "Patching isn’t available on this USB yet",
      html`The EnableGop injector GopForge uses (DXEInject) is a <strong>macOS program</strong> and can’t run on this Linux disk. Your backup is complete and safe —
      you can patch it with GopForge on macOS, or wait for the Linux injector.`)}</div>`)}
    ${jobBlock(j, { running: "Adding EnableGop…", done: "Patched image validated", failed: "Patching failed" })}
    ${when(S.br.patched, () => html`<div style="margin-top:var(--s5)">${fileCard(S.br.patched, "patched")}</div>`)}
    <div class="btn-row">
      <button class="btn" data-act="br-reset" ${jobRunning() ? "disabled" : ""}>Start Over</button>
      <span class="grow"></span>
      <button class="btn primary large" data-act="br-patch" ${blocked || (!ok && !expert) || jobRunning() ? "disabled" : ""}>${icon("layers")} Create Patched Image</button>
    </div>
  </div>`;
}

function viewFlash() {
  const b = S.br;
  const p = b.pfacts;
  const j = myJob("write-bootrom");
  return html`<div class="panel">
    ${panelHead(chipArt(), "Ready to flash", "Everything checks out. Review the details, then write the patched image to the Boot ROM.")}
    <div class="group checks">
      ${checkRow(p.size === b.facts.size ? "ok" : "bad", "Same size as your original", fmtExact(p.size))}
      ${checkRow(p.enablegop_count === 1 ? "ok" : "bad", "EnableGop installed exactly once", b.variant === "direct" ? "Direct variant" : "Standard variant")}
      ${checkRow(p.cmp_fingerprint ? "ok" : "bad", "Mac Pro firmware structure intact")}
    </div>
    ${section("What will be written", html`<div class="group">
      <div class="row">${sq("chip", "orange")}<div class="main-col"><div class="title">Target</div><div class="subtitle">Boot ROM · ${S.status.machine.model}</div></div></div>
      <div class="row">${sq("layers", "green")}<div class="main-col"><div class="title">New image</div><div class="subtitle">${b.patched.name} · <span class="mono">${shortHash(b.patched.sha256)}</span></div></div></div>
      <div class="row">${sq("archive", "blue")}<div class="main-col"><div class="title">Your backup</div><div class="subtitle">${b.dump.name} · <span class="mono">${shortHash(b.dump.sha256)}</span></div></div>${status("ok")}</div>
    </div>`)}
    <div style="margin-top:var(--s5)">${callout("danger", "Flashing firmware carries risk",
      html`If power is lost during the write the Mac may not start. Recovery then needs an SPI programmer (such as a CH341A) and the backup on this USB. See <span class="mono">docs/RECOVERY.md</span>.`)}</div>
    ${jobBlock(j, { running: "Writing…", done: "Boot ROM written and verified", failed: "The write did not complete" })}
    ${when(b.error, () => html`<div style="margin-top:var(--s4)">${callout("danger", "Don’t turn off your Mac yet",
      html`${b.error} The Boot ROM may be unchanged or partially written. Open Activity for details. You can retry the flash, or restore your backup from a shell with <span class="mono">flashrom -p internal -w ${b.dump.name}</span>.`)}</div>`)}
    <div class="btn-row">
      <button class="btn" data-act="br-reset" ${jobRunning() ? "disabled" : ""}>Start Over</button>
      <span class="grow"></span>
      <button class="btn destructive large" data-act="br-flash" ${jobRunning() ? "disabled" : ""}>${icon("bolt")} Flash Boot ROM…</button>
    </div>
  </div>`;
}

function viewFinish() {
  const tip = (n, t, d) => html`<div class="row"><span class="sq bg-blue" style="font-weight:700;font-size:13px">${n}</span>
    <div class="main-col"><div class="title">${t}</div><div class="subtitle">${d}</div></div></div>`;
  return html`<div class="panel">
    <div style="text-align:center">
      <div style="display:grid;place-items:center;margin:4px 0 14px">${successArt()}</div>
      <h2 class="t-title1">Boot ROM updated</h2>
      <p class="muted" style="margin:8px auto 0;max-width:56ch;line-height:1.5">EnableGop is now part of your Mac Pro’s firmware. A full power cycle completes the change.</p>
    </div>
    ${section("Next steps", html`<div class="group icons">
      ${tip(1, "Shut down completely", "Not restart — power off, wait a few seconds.")}
      ${tip(2, "Hold ⌥ Option while powering on", "The native startup picker should appear on your graphics card.")}
      ${tip(3, "Black until the picker is normal", "On non-Apple GPUs a plain boot may not draw the grey logo — the picker is the test.")}
      ${tip(4, "No picker at all?", "Try the Direct variant, or your card may also need GOP in its own firmware.")}
    </div>`, "Your original Boot ROM stays on this USB in gopforge-live › firmware › Backups.")}
    <div class="btn-row">
      <button class="btn" data-act="go" data-to="backups">${icon("archive")} View Backups</button>
      <span class="grow"></span>
      <button class="btn primary large" data-act="system" data-do="poweroff">${icon("power")} Shut Down</button>
    </div>
  </div>`;
}

export function render() {
  const m = S.status.machine;
  if (!(m.allow_bootrom || S.status.expert))
    return html`<div class="page">${locked("Boot ROM tools are for Mac Pro 4,1 and 5,1",
      html`This computer is ${m.model || "not an Apple Mac"}. ${m.class === "imac-gpu" ? "On iMacs the boot screen comes from the graphics firmware instead." : ""}`)}</div>`;
  const s = step();
  const body = { backup: viewBackup, inspect: viewInspect, already: viewAlready, patch: viewPatch, flash: viewFlash, finish: viewFinish }[s]();
  return html`<div class="page">
    <div class="page-head">
      <h1 class="t-large">Boot ROM</h1>
      <p>Give your Mac Pro a native boot screen and startup picker by adding EnableGop to its firmware — no OpenCore needed for the picker.</p>
    </div>
    ${steps(STEPS, s === "already" ? "finish" : s)}
    ${body}
  </div>`;
}
