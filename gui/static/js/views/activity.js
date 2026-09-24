// Activity — the session log that is also written to the USB.
import { html, raw, consoleLine } from "../dom.js";
import { icon } from "../icons.js";
import { api } from "../api.js";
import { S, actions, update } from "../core.js";

export const title = "Activity";

export async function enter() {
  const l = await api.get("/api/log?n=600");
  update({ log: l.ok ? l : { ok: false, text: l.error || "", path: "" } });
  setTimeout(() => { const c = document.getElementById("log-console"); if (c) c.scrollTop = c.scrollHeight; }, 0);
}

Object.assign(actions, { "log-refresh": enter });

export function render() {
  const l = S.log;
  return html`<div class="page" style="max-width:1080px">
    <div class="page-head" style="display:flex;align-items:flex-end;gap:16px">
      <div style="flex:1"><h1 class="t-large">Activity</h1>
        <p>Everything GopForge Live did this session. The same log is saved on the USB${l?.path ? ", in " : ""}${l?.path ? html`<span class="mono">${l.path.split("/").slice(-2).join("/")}</span>` : ""} — send it along if you need help.</p></div>
      <button class="btn" data-act="log-refresh">${icon("refresh")} Refresh</button>
    </div>
    <div class="console tall" id="log-console">${raw((l?.text || "Loading…").split("\n").map(consoleLine).join(""))}</div>
  </div>`;
}
