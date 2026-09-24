#!/usr/bin/env python3
"""GopForge-Live GUI backend.

A tiny, dependency-free (standard library only) local web server that
  * serves the single-page app in gui/static,
  * exposes a JSON API that shells out to bin/gfl-api (the same engine the text
    wizard uses — all safety gates live there, and are re-checked here), and
  * runs long hardware operations as background jobs whose output streams into
    the app's live console.

It binds to 127.0.0.1 only and every /api call must carry the per-boot token
that the kiosk session passes to Firefox in the URL.
"""
from __future__ import annotations

import argparse
import json
import mimetypes
import os
import re
import secrets
import shutil
import subprocess
import sys
import threading
import time
import uuid
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

ROOT = Path(__file__).resolve().parent.parent
API = ROOT / "bin" / "gfl-api"
STATIC = ROOT / "gui" / "static"
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
TEXTMODE_FLAG = Path("/run/gopforge-textmode")

# Actions that can run as jobs. "hw" jobs touch hardware and are mutually
# exclusive; "confirm" is the exact phrase the operator must have typed.
ACTIONS: dict[str, dict] = {
    "backup-gpu":     {"args": ["vendor", "index"], "hw": True},
    "flash-gpu":      {"args": ["vendor", "index", "rom", "backup", "model"], "hw": True, "confirm": "FLASH"},
    "dump-bootrom":   {"args": [], "hw": True},
    "check-bootrom":  {"args": ["dump"], "hw": False},
    "inject-bootrom": {"args": ["dump", "variant"], "hw": False},
    "write-bootrom":  {"args": ["patched", "dump"], "hw": True, "confirm": "FLASH BOOTROM"},
    "restore-bootrom": {"args": ["backup"], "hw": True, "confirm": "RESTORE BOOTROM"},
    "restore-gpu":    {"args": ["vendor", "index", "backup"], "hw": True, "confirm": "RESTORE"},
}
EXPERT_PHRASE = "I UNDERSTAND"


class Session:
    """Process-wide state: token, expert flag, jobs."""

    def __init__(self, token: str | None, mock: bool) -> None:
        self.token = token
        self.mock = mock
        self.expert = False
        self.jobs: dict[str, Job] = {}
        self.lock = threading.Lock()
        self.log_path: str | None = None

    def env(self, extra: dict[str, str] | None = None) -> dict[str, str]:
        env = os.environ.copy()
        env["GFL_EXPERT"] = "1" if self.expert else "0"
        env.pop("GFL_CONFIRM", None)
        if extra:
            env.update(extra)
        return env

    def note(self, msg: str) -> None:
        """Append a server event to the USB log (best effort)."""
        line = f"{time.strftime('%H:%M:%S')} [GUI] {msg}\n"
        sys.stderr.write(line)
        if self.log_path:
            try:
                with open(self.log_path, "a", encoding="utf-8") as fh:
                    fh.write(line)
            except OSError:
                pass

    def busy_hw(self) -> Job | None:
        with self.lock:
            for job in self.jobs.values():
                if job.hw and job.state == "running":
                    return job
        return None


SESSION: Session


def run_api(args: list[str], timeout: int = 90, extra_env: dict[str, str] | None = None) -> dict:
    """Run a quick (non-job) gfl-api command and return its JSON."""
    try:
        proc = subprocess.run(
            ["bash", str(API), *args], capture_output=True, text=True,
            timeout=timeout, env=SESSION.env(extra_env), errors="replace",
        )
    except subprocess.TimeoutExpired:
        return {"ok": False, "code": "timeout", "error": f"'{args[0]}' timed out"}
    return parse_result(proc.stdout, proc.returncode, proc.stderr)


def parse_result(stdout: str, code: int, stderr: str = "") -> dict:
    text = (stdout or "").strip()
    if text:
        try:
            return json.loads(text.splitlines()[-1])
        except json.JSONDecodeError:
            pass
    tail = ANSI.sub("", stderr or "").strip().splitlines()[-3:]
    return {"ok": False, "code": "backend", "error": "; ".join(tail) or f"backend exit {code}"}


class Job:
    def __init__(self, action: str, argv: list[str], hw: bool, confirm: str | None) -> None:
        self.id = uuid.uuid4().hex[:12]
        self.action = action
        self.argv = argv
        self.hw = hw
        self.confirm = confirm
        self.state = "running"
        self.lines: list[str] = []
        self.result: dict | None = None
        self.started = time.time()
        self.ended: float | None = None
        self._lock = threading.Lock()

    def start(self) -> None:
        threading.Thread(target=self._run, name=f"job-{self.action}", daemon=True).start()

    def _run(self) -> None:
        extra = {"GFL_CONFIRM": self.confirm} if self.confirm else None
        SESSION.note(f"job {self.id} start: {self.action} {' '.join(self.argv)}")
        try:
            proc = subprocess.Popen(
                ["bash", str(API), self.action, *self.argv],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                env=SESSION.env(extra), errors="replace", bufsize=1,
            )
            out_chunks: list[str] = []
            t = threading.Thread(target=lambda: out_chunks.append(proc.stdout.read()), daemon=True)
            t.start()
            assert proc.stderr is not None
            for raw in proc.stderr:
                line = ANSI.sub("", raw.rstrip("\n"))
                if line.strip():
                    with self._lock:
                        self.lines.append(line)
            code = proc.wait()
            t.join(timeout=5)
            result = parse_result("".join(out_chunks), code)
        except Exception as exc:  # pragma: no cover - defensive
            code, result = 1, {"ok": False, "code": "server", "error": str(exc)}
        with self._lock:
            self.result = result
            self.state = "done" if result.get("ok") else ("refused" if code == 2 else "failed")
            self.ended = time.time()
        SESSION.note(f"job {self.id} {self.state}: {self.action} → {result.get('code') or 'ok'}")

    def view(self, since: int) -> dict:
        with self._lock:
            return {
                "id": self.id, "action": self.action, "state": self.state,
                "lines": self.lines[since:], "next": len(self.lines),
                "result": self.result, "started": self.started, "ended": self.ended,
            }


def system_action(action: str) -> dict:
    SESSION.note(f"system action: {action}")
    if SESSION.mock:
        return {"ok": True, "mock": True, "action": action}
    subprocess.run(["sync"], check=False)
    if action == "textmode":
        TEXTMODE_FLAG.write_text("1")
        # Closing the browser ends the kiosk session; autostart then runs the TUI.
        threading.Timer(0.5, lambda: subprocess.run(["pkill", "-f", "firefox"], check=False)).start()
        return {"ok": True}
    if action in ("poweroff", "reboot"):
        threading.Timer(0.8, lambda: subprocess.run(["systemctl", action], check=False)).start()
        return {"ok": True}
    return {"ok": False, "code": "usage", "error": f"unknown action {action}"}


class Handler(BaseHTTPRequestHandler):
    server_version = "GopForgeLive/1"

    # --- plumbing -------------------------------------------------------------
    def log_message(self, fmt: str, *args) -> None:  # quieter console
        first = str(args[0]) if args else ""
        if "/api/jobs/" not in first:
            sys.stderr.write("%s %s\n" % (self.address_string(), fmt % args))

    def send_json(self, obj: dict, status: int = 200) -> None:
        body = json.dumps(obj).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def read_json(self) -> dict:
        n = int(self.headers.get("Content-Length") or 0)
        if n <= 0 or n > 1 << 20:
            return {}
        try:
            return json.loads(self.rfile.read(n) or b"{}")
        except json.JSONDecodeError:
            return {}

    def authorised(self) -> bool:
        return SESSION.token is None or secrets.compare_digest(
            self.headers.get("X-GFL-Token", ""), SESSION.token)

    def serve_static(self, rel: str) -> None:
        rel = rel.lstrip("/") or "index.html"
        root = STATIC.resolve()
        path = (root / rel).resolve()
        if root not in path.parents or not path.is_file():   # no traversal outside static/
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        ctype = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        if path.suffix == ".js":
            ctype = "text/javascript"
        data = path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", ctype + ("; charset=utf-8" if ctype.startswith("text/") else ""))
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    # --- routes -----------------------------------------------------------------
    def do_GET(self) -> None:
        url = urlparse(self.path)
        if not url.path.startswith("/api/"):
            return self.serve_static(url.path)
        if not self.authorised():
            return self.send_json({"ok": False, "code": "auth", "error": "bad token"}, 403)
        q = {k: v[0] for k, v in parse_qs(url.query).items()}
        route = url.path[len("/api/"):]

        if route == "ping":
            return self.send_json({"ok": True, "mock": SESSION.mock, "expert": SESSION.expert})
        if route == "status":
            res = run_api(["status"])
            if res.get("ok"):
                SESSION.log_path = res.get("storage", {}).get("log") or SESSION.log_path
                res["expert"] = SESSION.expert
                res["busy"] = bool(SESSION.busy_hw())
            return self.send_json(res)
        if route in ("hardware", "gpus", "library", "backups"):
            return self.send_json(run_api([route]))
        if route == "model":
            return self.send_json(run_api(["model"] + ([q["key"]] if q.get("key") else [])))
        if route == "plan":
            args = ["plan", q.get("gpu", "0")] + ([q["model"]] if q.get("model") else [])
            return self.send_json(run_api(args))
        if route == "adapters":
            return self.send_json(run_api(["adapters", q.get("vendor", "")]))
        if route == "log":
            return self.send_json(run_api(["log", q.get("n", "400")]))
        if route.startswith("jobs/"):
            job = SESSION.jobs.get(route[5:])
            if not job:
                return self.send_json({"ok": False, "code": "no_job", "error": "unknown job"}, 404)
            return self.send_json({"ok": True, "job": job.view(int(q.get("since", "0") or 0))})
        return self.send_json({"ok": False, "code": "no_route", "error": route}, 404)

    def do_POST(self) -> None:
        url = urlparse(self.path)
        if not self.authorised():
            return self.send_json({"ok": False, "code": "auth", "error": "bad token"}, 403)
        body = self.read_json()
        route = url.path[len("/api/"):] if url.path.startswith("/api/") else ""

        if route == "expert":
            if body.get("enable"):
                if str(body.get("phrase", "")).strip().upper() != EXPERT_PHRASE:
                    return self.send_json({"ok": False, "code": "unconfirmed",
                                           "error": f"type {EXPERT_PHRASE} to enable Expert mode"}, 400)
                SESSION.expert = True
            else:
                SESSION.expert = False
            SESSION.note(f"expert mode {'ON' if SESSION.expert else 'off'}")
            return self.send_json({"ok": True, "expert": SESSION.expert})

        if route == "jobs":
            action = body.get("action", "")
            spec = ACTIONS.get(action)
            if not spec:
                return self.send_json({"ok": False, "code": "usage", "error": f"unknown action {action}"}, 400)
            args = body.get("args") or {}
            argv = [str(args.get(k, "")) for k in spec["args"]]
            while argv and argv[-1] == "" and spec["args"][len(argv) - 1] == "model":
                argv.pop()  # optional trailing arg
            if any(a == "" for a in argv):
                return self.send_json({"ok": False, "code": "usage", "error": "missing arguments"}, 400)
            confirm = None
            if spec.get("confirm"):
                if str(body.get("confirm", "")).strip() != spec["confirm"]:
                    return self.send_json({"ok": False, "code": "unconfirmed",
                                           "error": f"type {spec['confirm']} to confirm"}, 400)
                confirm = spec["confirm"]
            if spec["hw"]:
                busy = SESSION.busy_hw()
                if busy:
                    return self.send_json({"ok": False, "code": "busy",
                                           "error": f"'{busy.action}' is still running"}, 409)
            job = Job(action, argv, spec["hw"], confirm)
            with SESSION.lock:
                SESSION.jobs[job.id] = job
            job.start()
            return self.send_json({"ok": True, "job": job.view(0)})

        if route == "system":
            return self.send_json(system_action(str(body.get("action", ""))))

        return self.send_json({"ok": False, "code": "no_route", "error": route}, 404)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--token", help="API token (generated if omitted)")
    ap.add_argument("--token-file", help="write the token here (for the kiosk launcher)")
    ap.add_argument("--no-token", action="store_true", help="disable the token (dev only)")
    args = ap.parse_args()

    global SESSION
    mock = os.environ.get("GFL_MOCK") == "1"
    token = None if args.no_token else (args.token or secrets.token_urlsafe(24))
    SESSION = Session(token, mock)
    if token and args.token_file:
        Path(args.token_file).write_text(token)
    if not shutil.which("bash"):
        sys.exit("bash is required")

    httpd = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    httpd.daemon_threads = True
    sys.stderr.write(f"GopForge-Live GUI on http://127.0.0.1:{args.port}/ "
                     f"({'MOCK hardware' if mock else 'real hardware'})\n")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
