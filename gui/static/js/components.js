// components.js — reusable UI building blocks.
import { html, raw, when, fmtBytes, fmtExact, shortHash, onUsbPath, consoleLine } from "./dom.js";
import { icon, status, spinner, sq } from "./icons.js";
import { fileArt } from "./art.js";
import { S } from "./core.js";
import { method } from "./macs.js";

export const section = (title, body, foot = "") => html`
  <div class="section">
    ${when(title, () => html`<div class="section-title">${title}</div>`)}
    ${body}
    ${when(foot, () => html`<div class="section-foot">${foot}</div>`)}
  </div>`;

export const callout = (kind, title, body = "", iconName) => html`
  <div class="callout ${kind}">
    ${icon(iconName || { info: "info", warn: "alert", danger: "alert", success: "shieldCheck" }[kind] || "info")}
    <div>${when(title, () => html`<div class="c-title">${title}</div>`)}<div class="c-body">${body}</div></div>
  </div>`;

export const checkRow = (level, title, sub = "") => html`
  <div class="row">${status(level)}
    <div class="main-col"><div class="title">${title}</div>${when(sub, () => html`<div class="subtitle">${sub}</div>`)}</div>
  </div>`;

export const kv = (k, v) => html`<div><div class="k">${k}</div><div class="v" title="${typeof v === "string" ? v : ""}">${v}</div></div>`;

export function steps(list, current) {
  const idx = list.findIndex((s) => s.id === current);
  return html`<div class="steps" role="list">${list.map((s, i) => html`
    <div class="step ${i < idx ? "done" : i === idx ? "current" : ""}" role="listitem" aria-current="${i === idx ? "step" : "false"}">
      <div class="bubble">${i < idx ? icon("check") : i + 1}</div>
      <div class="lbl">${s.label}</div>
    </div>`)}</div>`;
}

export function fileCard(f, kind, extra = "") {
  if (!f) return "";
  return html`
    <div class="file-card">
      ${fileArt(kind)}
      <div class="main-col" style="flex:1;min-width:0">
        <div class="fc-name">${f.name}</div>
        <div class="fc-meta">${fmtBytes(f.size)} (${fmtExact(f.size)}) · SHA-256 <span class="mono">${shortHash(f.sha256)}</span></div>
        <div class="fc-meta">${onUsbPath(f.path, S.status?.storage)}</div>
      </div>
      ${extra}
    </div>`;
}

export const methodBadge = (m) => html`<span class="badge ${m}">${method(m).label}</span>`;

/** Inline running/finished job panel with live console. */
export function jobBlock(job, labels = {}) {
  if (!job) return "";
  const running = job.state === "running";
  const ok = job.state === "done";
  const open = !!S.ui.console[job.id];
  const lvl = running ? null : ok ? "ok" : job.state === "refused" ? "warn" : "bad";
  const title = running ? (labels.running || job.title) : ok ? (labels.done || "Done") : (labels.failed || "Didn’t complete");
  const last = job.lines.length ? job.lines[job.lines.length - 1].replace(/^\d\d:\d\d:\d\d \[\w+\] /, "") : "Starting…";
  return html`
    <div class="run">
      <div class="run-head">
        ${running ? spinner() : status(lvl)}
        <div class="run-title">${title}</div>
        <span class="elapsed" data-since="${job.started}" ${job.ended ? raw(`data-until="${job.ended}"`) : ""}></span>
      </div>
      <div class="progress ${running ? "indeterminate" : ok ? "done" : "fail"}"><i></i></div>
      ${when(!ok && !running && job.result?.error, () => html`<div class="t-footnote" style="margin-top:10px;color:var(--label)">${job.result.error}</div>`)}
      ${when(running, () => html`<div class="t-caption faint mono" id="last-${job.id}" style="margin-top:8px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${last}</div>`)}
      <button class="disclose ${open ? "open" : ""}" data-act="toggle-console" data-id="${job.id}">${icon("chevronRight")} ${open ? "Hide Details" : "Show Details"}</button>
      <div class="console" id="console-${job.id}" ${open ? "" : raw("hidden")}>${raw(job.lines.map(consoleLine).join(""))}</div>
    </div>`;
}

/** Locked (gated) state for a flow page. */
export const locked = (title, body) => html`
  <div class="empty">
    <div class="e-icon">${icon("lock")}</div>
    <h2 class="t-title2">${title}</h2>
    <p>${body}</p>
    <div class="btn-row" style="justify-content:center">
      <button class="btn" data-act="go" data-to="overview">Back to Overview</button>
      <button class="btn" data-act="sheet" data-sheet="expert">${icon("wrench")} Expert Mode…</button>
    </div>
  </div>`;

export const navRow = (to, sqIcon, color, title, subtitle, trailing = "") => html`
  <div class="row link tall" tabindex="0" role="button" data-act="go" data-to="${to}">
    ${sq(sqIcon, color, "lg")}
    <div class="main-col"><div class="title">${title}</div><div class="subtitle">${subtitle}</div></div>
    ${trailing}${icon("chevronRight", "chev")}
  </div>`;
