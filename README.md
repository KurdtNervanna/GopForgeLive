# GopForge-Live

**An all-in-one, bootable GOP boot-screen flashing wizard for EFI-era Macs.**

> ⚠️ **Status: `0.3.0-beta`.** Boots straight into the app on a real Mac Pro 5,1 and a
> 27" iMac12,2, and reads/backs up firmware on real hardware. Its Linux EnableGop
> injector produces a DXE volume byte-identical to dosdude1's DXEInject on a real
> MacPro5,1 Boot ROM. **No firmware has yet been flashed by GopForge-Live on real
> hardware** — treat flashing as experimental, follow [docs/TESTING.md](docs/TESTING.md),
> and don't flash a machine you can't recover ([docs/RECOVERY.md](docs/RECOVERY.md)).

GopForge-Live is a guided app (with a text-mode fallback) that runs inside the
[GRML-FLASH](https://github.com/Ausdauersportler/GRML-FLASH) live environment and
automates the whole path to a native pre-boot picker on an old Mac with a modern
GPU:

1. **Detect** the Mac model (`dmidecode`) and installed GPU(s) (`lspci`).
2. **Recommend** a known-good, GOP-enabled vBIOS from a curated catalog.
3. **Back up and flash** the GPU vBIOS (`amdvbflash` / `nvflash`).
4. **Dump → patch → flash** the Mac BootROM: `flashrom` reads it,
   [GopForge](https://github.com/KurdtNervanna/GopForge) injects EnableGop, and
   `flashrom` writes it back — all on Linux. GopForge's injector (dosdude1's
   DXEInject) is macOS-only, so the USB carries a Linux build of the same engine:
   [tools/dxeinject-linux](tools/dxeinject-linux/README.md) (validated against
   Apple's MP51.fd 144.0.0.0.0).

## The app

The USB boots straight into a full-screen, macOS-style app (Firefox kiosk + a local
Python backend over the same engine as the text wizard): a device overview, guided
**Boot ROM** and **Graphics Card** flows with live progress, backups, the ROM library
and an activity log. It falls back to the text wizard automatically if graphics can't
start. See [docs/GUI.md](docs/GUI.md) — including `dev/run-gui-dev.sh`, which runs the
app against simulated hardware on any Linux/WSL box.

## Why it exists

GRML-FLASH gives you the tools but makes you drive them by hand. GopForge injects
EnableGop but relies on macOS-only Rom Dump to dump/flash the BootROM. GopForge-Live
stitches them together: `flashrom` *is* the dump/flash step GopForge leaves out, so
one USB does both the **GPU vBIOS** side and the **BootROM** side, with detection,
recommendation, mandatory backups, and confirmations wrapped around them.

## Layout

```
bin/gopwizard.sh        # text wizard (whiptail; falls back to plain prompts)
bin/gfl-api             # JSON API over the engine (used by the GUI)
gui/                    # graphical app: server.py, session.sh, static/ SPA, firefox/ prefs
dev/                    # run-gui-dev.sh + mock hardware for developing off-Mac
bin/lib/                # ui, detect, library, vbios, bootrom, safety
catalog/                # imac-boot-screen-matrix.json + SCHEMA.md (model/panel/memory rules)
docs/                   # INSTALL / TESTING / WORKFLOW / RECOVERY / GUI / REMASTER
tools/                  # fetch-vendor, fetch-roms, dxeinject-linux, install-to-usb, remaster-image
flash-usb/              # Windows/macOS/Linux USB writers + base-image fetcher
vendor/gopforge/        # populated by tools/fetch-vendor.sh (not committed)
roms/                   # full IMAC-EFI-BOOT-SCREEN vBIOS library (GPL-3.0, fetched, not committed)
```

## Make the bootable USB (Windows / macOS / Linux)

```bash
./tools/fetch-vendor.sh                 # GopForge + EnableGop tooling
./tools/fetch-roms.sh                   # the whole IMAC-EFI-BOOT-SCREEN vBIOS library
sudo ./tools/dxeinject-linux/build.sh   # Linux DXEInject (Boot ROM patching on the USB)
./flash-usb/get-base-image.sh           # download the GRML-FLASH base image
sudo ./flash-usb/write-image-linux.sh <image.img> /dev/sdX      # Linux
sudo ./flash-usb/write-image-macos.sh <image.img> /dev/diskN    # macOS
#   Windows (elevated PowerShell):
#   .\flash-usb\write-image-windows.ps1 -Image C:\path\grml-flash.img
```

Each writer erases the stick, writes the bootable image, and copies the wizard +
ROM library onto its FAT partition. See [flash-usb/README.md](flash-usb/README.md).
(Already have a GRML-FLASH USB? Skip the writers and use
`./tools/install-to-usb.sh /mnt/usb`.)

**All-in-one auto-launch image (Linux):** `tools/remaster-image.sh` bakes the wizard +
ROM library into a single bootable file that launches on boot (via an additive
live-boot squashfs module — the base image's Mac/PC boot is left untouched):
```bash
sudo ./tools/remaster-image.sh --img grml-flash.img --out gopforge-live.img
sudo ./flash-usb/write-image-linux.sh gopforge-live.img /dev/sdX --no-install
```
See [docs/REMASTER.md](docs/REMASTER.md). This is the recommended path: its auto-launch
is verified in QEMU (UEFI) and on a real Mac Pro. (`tools/build-image.sh`, which wires
autostart onto the data partition without remastering, is older and untested.)

## Boot the target machine

Power on the Mac holding **⌥ Option** and pick the USB (**EFI Boot**). The remastered
image opens the app automatically (text wizard as fallback); on a plain GRML-FLASH USB
run `sudo bash bin/gopwizard.sh`. It **detects the machine and offers only what applies**:

| Machine | Offered |
|---------|---------|
| Mac Pro 5,1 / 4,1 | BootROM EnableGop (dump → GopForge → flash). GPU flash off. |
| Supported iMac (2009–2011) | Guided GPU vBIOS flashing. BootROM path off. |
| Mac Pro 3,1 & earlier / other / non-Apple | Nothing (Expert override available). |

See [docs/INSTALL.md](docs/INSTALL.md) and [docs/WORKFLOW.md](docs/WORKFLOW.md).

## Safety model

- The wizard is **machine-gated**: it will not offer a path that doesn't apply to
  the detected machine (an unsupported machine gets nothing unless you knowingly
  enable the Expert override).
- Every hardware write is preceded by a **verified backup** (size + sha256), and
  **Backups › Restore** puts any of them back from inside the app.
- GPU ROMs are recommended from the **iMac boot-screen matrix**, which detects your
  iMac model + GPU and marks each candidate **✓ suitable / ⚠ caution / ✗ won't work**
  (Polaris has no LVDS; iMac9,1 needs EnableGop91; memory-vendor ROMs must match your
  VRAM). A ✗ from a method the model *forbids* (e.g. **EG2 white-screens on iMac10,1
  A1312**) is **hard-blocked**. Where `dmidecode` is ambiguous (iMac10,1 A1311 vs
  A1312) the wizard asks which model you have first.
- BootROM writes require a **double confirmation**; GopForge itself refuses to
  patch anything that isn't a MacPro4,1/5,1 image. A patched BootROM may differ from
  the backup **only inside the DXE volume** — NVRAM, serial/board data, microcode and
  the boot block must be byte-identical, or it is discarded / refused for writing.
  The chip is re-read right before the write and must still equal that backup.
- Read [docs/RECOVERY.md](docs/RECOVERY.md) and keep a CH341A handy for the
  BootROM path.

## Credits

Builds on [Ausdauersportler/GRML-FLASH](https://github.com/Ausdauersportler/GRML-FLASH),
[KurdtNervanna/GopForge](https://github.com/KurdtNervanna/GopForge),
acidanthera's EnableGop, dosdude1's DXEInject, and
[LongSoft/UEFITool](https://github.com/LongSoft/UEFITool) (the engine behind the Linux
injector, BSD-2-Clause). Not affiliated with Apple.

## License

MIT — see [LICENSE](LICENSE).
