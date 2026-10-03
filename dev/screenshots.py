#!/usr/bin/env python3
"""Capture the README screenshots (docs/screenshots/) from the app running on
simulated hardware — nothing real is touched.

Needs: WSL (or Linux) for dev/run-gui-dev.sh, and Playwright for Python driving an
installed Edge/Chrome:   pip install playwright
Usage (from the repo root on Windows):   py dev/screenshots.py
"""
import subprocess, sys, time, urllib.request
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent.parent
OUT = REPO / "docs" / "screenshots"
URL = "http://localhost:8765/"
VIEW = {"width": 1440, "height": 900}
ON_WINDOWS = sys.platform == "win32"


def sh(cmd: str, background: bool = False):
    """Run a bash command in the repo (through WSL on Windows)."""
    wsl_repo = "/mnt/" + str(REPO)[0].lower() + str(REPO)[2:].replace("\\", "/") if ON_WINDOWS else str(REPO)
    argv = (["wsl.exe", "--", "bash", "-c"] if ON_WINDOWS else ["bash", "-c"]) + [f"cd '{wsl_repo}' && {cmd}"]
    if background:
        return subprocess.Popen(argv, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return subprocess.run(argv, check=False)


def serve(model: str, gpu: str):
    sh("pkill -f 'gui/serve[r].py'; rm -rf dev/mock/usb/gopforge-live")
    proc = sh(f"GFL_MOCK_FAST=1 bash dev/run-gui-dev.sh {model} {gpu}", background=True)
    for _ in range(60):
        try:
            urllib.request.urlopen(URL + "api/ping", timeout=1)
            return proc
        except Exception:
            time.sleep(0.5)
    sys.exit("dev server did not start")


def stop():
    sh("pkill -f 'gui/serve[r].py'; rm -rf dev/mock/usb/gopforge-live")


# The README says these come from simulated hardware, so the "Demo" badges are
# hidden to keep the shots clean; toasts are transient and removed too.
CLEAN = r"""document.querySelectorAll('.toast').forEach(e => e.remove());
document.querySelectorAll('.pill').forEach(e => { if (/\bDemo\b/.test(e.textContent)) e.remove(); });"""


def settle(page):
    page.wait_for_timeout(300)
    page.wait_for_function("document.getAnimations().every(a => a.playState !== 'running')", timeout=10000)
    page.wait_for_timeout(200)


def shot(page, name: str, scroll_to: str | None = None, top: bool = False):
    if top:
        page.evaluate("document.getElementById('scroller').scrollTop = 0")
    if scroll_to:
        page.locator(scroll_to).first.scroll_into_view_if_needed()
    settle(page)
    page.evaluate(CLEAN)
    page.screenshot(path=str(OUT / f"{name}.png"))
    print("  ok", name)


def act(page, a: str):
    page.locator(f'[data-act="{a}"]:not([disabled])').first.click()


def run(browser):
    OUT.mkdir(parents=True, exist_ok=True)

    print("Mac Pro 5,1 + Radeon RX Vega 64")
    serve("MacPro5,1", "vega64")
    page = browser.new_page(viewport=VIEW, device_scale_factor=2, color_scheme="dark")
    page.goto(URL + "#/overview"); page.wait_for_selector("#page .hero, #page h1")
    shot(page, "overview-macpro")
    page.goto(URL + "#/bootrom"); act(page, "br-dump")
    page.wait_for_selector('[data-act="br-patch"]:not([disabled])', timeout=30000)
    shot(page, "bootrom-patch", scroll_to=".choices")
    act(page, "br-patch")
    page.wait_for_selector('[data-act="br-flash"]:not([disabled])', timeout=30000)
    shot(page, "bootrom-flash", top=True)
    act(page, "br-flash"); page.wait_for_selector("#confirm-field")
    page.type("#confirm-field", "FLASH BOOTROM"); page.wait_for_timeout(3300)   # button arms after 3 s
    shot(page, "bootrom-confirm")
    page.keyboard.press("Escape")
    page.goto(URL + "#/backups"); page.wait_for_selector('[data-act="backups-restore"]'); page.wait_for_timeout(600)
    shot(page, "backups")
    page.close(); stop()

    print("iMac12,2 (27-inch) + Radeon Pro WX 7100 Mobile")
    serve("iMac12,2", "wx7100")
    page = browser.new_page(viewport=VIEW, device_scale_factor=2, color_scheme="light")
    page.goto(URL + "#/overview"); page.wait_for_selector("#page .hero, #page h1")
    if page.evaluate("document.documentElement.dataset.theme") != "light":
        act(page, "toggle-theme")
    shot(page, "overview-imac-light")
    page.goto(URL + "#/gpu"); page.wait_for_selector('[data-act="gpu-next"]')
    if page.evaluate("document.documentElement.dataset.theme") == "light":
        act(page, "toggle-theme")
    act(page, "gpu-next"); page.wait_for_selector('[data-act="gpu-rom"]')
    shot(page, "gpu-firmware")
    page.close(); stop()


if __name__ == "__main__":
    with sync_playwright() as p:
        try:
            browser = p.chromium.launch(channel="msedge")
        except Exception:
            browser = p.chromium.launch(channel="chrome")
        try:
            run(browser)
        finally:
            browser.close(); stop()
    print(f"saved to {OUT}")
