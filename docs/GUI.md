# The graphical app

GopForge Live boots straight into a full-screen, macOS-style app. It does exactly what
the text wizard does — same engine, same safety gates — with guided, step-by-step
screens instead of menus.

## What you'll see

| Page | What it does |
|------|--------------|
| **Overview** | This Mac (drawn Mac Pro / iMac), its processors, memory and Boot ROM version, what the disk can do for it, and the status of every tool. **Full Hardware Report** lists CPUs, memory modules, PCI/USB devices, Wi-Fi, Bluetooth, disks and sensors, and saves it to `gopforge-live/reports/` on the USB. |
| **Add GOP cMP** *(Mac Pro 4,1 / 5,1)* | Back Up → Inspect → Patch → Flash → Finish. Adds EnableGop to the Boot ROM. |
| **4,1→5,1 Crossflash** *(Mac Pro 4,1 / 5,1)* | Template → Back Up → Build → Flash → Finish. Rebuilds the Boot ROM on a clean 144.0.0.0.0 template with your serial number and MAC address — the 4,1 → 5,1 crossflash (experimental; a 4,1 needs Expert Mode). |
| **Graphics Card** *(iMac 2009–2011)* | Card → Firmware → Back Up → Flash → Finish. Recommends GOP firmware for your exact card and display. If nothing matches, **Back Up for Submission** saves the card's firmware plus a README with its IDs to `gopforge-live/submissions/` and points you to where to share it. **Post on MacRumors…** opens the iMac graphics-upgrade thread in a hidden browser tab (Ethernet needed): sign in, attach the file from *Home › GopForge submissions*, and press **Ctrl+W** to come back. TechPowerUp's BIOS collection only takes uploads from GPU-Z on Windows. On a Mac Pro this page only backs up the card's firmware (flashing needs Expert Mode). |
| **Backups** | Every firmware image saved to the USB, with **Restore** for original Boot ROM and graphics-firmware backups. |
| **ROM Library** | The full IMAC-EFI-BOOT-SCREEN collection, searchable. |
| **Activity** | The session log (also saved to the USB). |

Pages that don't apply to the detected Mac are locked (🔒). **Settings** has Light/Dark
appearance, three text sizes (handy on a 27-inch iMac), Expert Mode, and *Switch to
Text Mode*. The **power** button offers Restart, Shut Down and Text Mode.

## Safety — enforced by the engine, not just the screens

Every write is re-checked by `bin/gfl-api` no matter what the app sends:

- machine gating (Mac Pro → Boot ROM only; iMac → graphics firmware only) unless
  Expert Mode is on (typed `I UNDERSTAND`),
- a verified backup of *that* card / chip on the USB before anything is flashed,
- firmware known not to work on your model (e.g. EG2 on the 27-inch iMac10,1) is
  blocked,
- Boot ROM images must be 4 MB with the Mac Pro fingerprint and exactly one EnableGop,
- a patched Boot ROM may differ from your backup **only inside the DXE volume** — NVRAM,
  serial/board data, microcode and the boot block must be byte-identical,
- right before a Boot ROM write the chip is re-read and must still equal the backup, and
  flashrom must not report that region as write-protected (Mac Pros need *flash mode*:
  power button held until the beep),
- flashing requires typing `FLASH` / `FLASH BOOTROM` (restoring: `RESTORE` /
  `RESTORE BOOTROM`), and the button only arms after three seconds.

While firmware is being written a full-screen panel blocks the app and reminds you not
to turn the Mac off.

## Big screens

On screens 2400 px wide or more (the 27" iMac's 2560×1440), the app renders at 1.5×, and
at 2× from 3600 px. With no window manager, `gui/session.sh` sizes the Firefox window to
the screen *in CSS pixels* (screen ÷ scale). If the window still ends up larger than the
screen, the app pins itself to the visible area; if it comes up the wrong size (one Mac
Pro got 1024×576 on a 1920×1080 screen), Firefox is relaunched once, with a fresh
profile, at the size it measured itself. Each session logs its real viewport to the USB
log (`display: viewport …`). To force a size, add `gfl.window=WIDTHxHEIGHT` (CSS pixels)
to the boot line.

## If the app doesn't appear

The disk falls back to the text wizard automatically if X or Firefox can't start (for
example on an unusual graphics card), or if the app closes. Details are in
`/run/gopforge-gui/session.log` and `xinit.log`.

Escape hatches — create an empty file with this name at the top of the USB (from any
computer):

- `gopforge-tui` — skip the graphical app and go straight to the text wizard
- `gopforge-plain` — text wizard with plain numbered menus

You can also press **Ctrl-C** during the 3-second countdown for a shell, or SSH in as
`root` (password `flash`).

## How it works

```
gopforge.service (tty1)
  └ bin/autostart.sh ── xinit ──▶ gui/session.sh (X on vt7)
                                    ├ gui/server.py   127.0.0.1:8765, per-boot token
                                    │   └ bin/gfl-api <command>   (JSON over the engine)
                                    └ firefox-esr --kiosk  →  gui/static (single-page app)
      ◀── on exit / failure / "Text Mode": bin/gopwizard.sh (text wizard)
```

- `gui/server.py` — standard-library Python. Runs long operations as jobs and streams
  their output into the app's console.
- `gui/static/` — vanilla JS modules + CSS, no build step, no network. Inter and
  JetBrains Mono are bundled (SIL OFL). Targets Firefox ESR 115.
- `gui/firefox/user.js` — kiosk prefs: no first-run pages, telemetry, updates or
  network probes; software rendering for odd GPUs.

## Developing without a Mac

`dev/run-gui-dev.sh` runs the app against **simulated hardware** — nothing real is
touched, no root needed (Linux or WSL):

```bash
dev/run-gui-dev.sh MacPro5,1 vega64      # then open http://localhost:8765/
dev/run-gui-dev.sh iMac10,1 wx4150        # the "which iMac?" + shared-ID card flow
dev/run-gui-dev.sh PC none                # unsupported machine
GFL_MOCK_FAIL=write dev/run-gui-dev.sh    # make the Boot ROM write fail
GFL_MOCK_DRIFT=1 dev/run-gui-dev.sh       # NVRAM changes between reads → stale-backup path
GFL_MOCK_LOCKED=1 dev/run-gui-dev.sh      # chip write-protected like a normal cMP boot
```

`dev/screenshots.py` regenerates the README screenshots (`docs/screenshots/`) from these
simulated machines using Playwright and an installed Edge/Chrome
(`pip install playwright`, then `py dev/screenshots.py`).

The simulated chip remembers writes (`dev/mock/usb/.mock-chip.rom`), so flash → restore
round-trips behave like the real thing.
