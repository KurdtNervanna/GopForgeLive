// api.js — talks to the local backend. The per-boot token arrives in the URL
// (?t=…) from the kiosk launcher; it's kept for reloads in sessionStorage.
const params = new URLSearchParams(location.search);
let token = params.get("t") || "";
try {
  if (token) sessionStorage.setItem("gfl-token", token);
  else token = sessionStorage.getItem("gfl-token") || "";
} catch { /* storage unavailable — fine */ }

async function req(method, path, body) {
  try {
    const res = await fetch(path, {
      method,
      headers: { "X-GFL-Token": token, "Content-Type": "application/json" },
      body: body === undefined ? undefined : JSON.stringify(body),
      cache: "no-store",
    });
    try { return await res.json(); }
    catch { return { ok: false, code: "http", error: `HTTP ${res.status}` }; }
  } catch (e) {
    return { ok: false, code: "offline", error: "The GopForge backend is not responding." };
  }
}

export const api = {
  get: (p) => req("GET", p),
  post: (p, b) => req("POST", p, b ?? {}),
};
