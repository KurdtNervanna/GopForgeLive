# GopForge-Live

**An all-in-one, bootable GOP boot-screen flashing wizard for EFI-era Macs.**

> ⚠️ **Status: `0.1.0-untested`.** Nothing here has been run against real
> hardware yet. Do not flash a machine you can't recover (see
> [docs/RECOVERY.md](docs/RECOVERY.md)). This repo is private until it's tested.

GopForge-Live is a TUI wizard that runs inside the
[GRML-FLASH](https://github.com/Ausdauersportler/GRML-FLASH) live environment and
automates the whole path to a native pre-boot picker on an old Mac with a modern
GPU:

1. **Detect** the Mac model (`dmidecode`) and installed GPU(s) (`lspci`).
2. **Recommend** a known-good, GOP-enabled vBIOS from a curated catalog.
3. **Back up and flash** the GPU vBIOS (`amdvbflash` / `nvflash`).
4. **Dump → patch → flash** the Mac BootROM: `flashrom` reads it,
   [GopForge](https://github.com/KurdtNervanna/GopForge) injects EnableGop, and
   `flashrom` writes it back — the whole thing on Linux, no macOS needed.

## Why it exists

GRML-FLASH gives you the tools but makes you drive them by hand. GopForge injects
EnableGop but relies on macOS-only Rom Dump to dump/flash the BootROM. GopForge-Live
stitches them together: `flashrom` *is* the dump/flash step GopForge leaves out, so
one USB does both the **GPU vBIOS** side and the **BootROM** side, with detection,
recommendation, mandatory backups, and confirmations wrapped around them.

## Layout

```
bin/gopwizard.sh        # main TUI (whiptail; falls back to plain prompts)
bin/lib/                # ui, detect, library, vbios, bootrom, safety
catalog/                # imac-boot-screen-matrix.json + SCHEMA.md (model/panel/memory rules)
docs/                   # WORKFLOW / INSTALL / RECOVERY
tools/                  # fetch-vendor, fetch-roms, install-to-usb, build-image (stub)
vendor/gopforge/        # populated by tools/fetch-vendor.sh (not committed)
roms/                   # full IMAC-EFI-BOOT-SCREEN vBIOS library (GPL-3.0, fetched, not committed)
```

## Quick start

```bash
./tools/fetch-vendor.sh                 # pull GopForge + EnableGop tooling
./tools/fetch-roms.sh                   # pull the whole IMAC-EFI-BOOT-SCREEN vBIOS library
./tools/install-to-usb.sh /mnt/usb      # onto a GRML-FLASH USB's data partition
# boot the Mac from that USB, then:
sudo bash bin/gopwizard.sh
```

See [docs/INSTALL.md](docs/INSTALL.md) for the full setup and
[docs/WORKFLOW.md](docs/WORKFLOW.md) for which branch (GPU vs BootROM) you need.

## Safety model

- Every hardware write is preceded by a **verified backup** (size + sha256).
- GPU ROMs are recommended from the **iMac boot-screen matrix**, which detects your
  iMac model + GPU and marks each candidate **✓ suitable / ⚠ caution / ✗ won't work**
  (e.g. EG2 white-screens on iMac10,1 A1312; Polaris has no LVDS; iMac9,1 needs
  EnableGop91; memory-vendor ROMs must match your VRAM). It warns on ✗ but doesn't
  hard-block, since edge cases exist.
- BootROM writes require a **double confirmation**; GopForge itself refuses to
  patch anything that isn't a MacPro4,1/5,1 image.
- Read [docs/RECOVERY.md](docs/RECOVERY.md) and keep a CH341A handy for the
  BootROM path.

## Credits

Builds on [Ausdauersportler/GRML-FLASH](https://github.com/Ausdauersportler/GRML-FLASH),
[KurdtNervanna/GopForge](https://github.com/KurdtNervanna/GopForge), and
acidanthera's EnableGop. Not affiliated with Apple.

## License

MIT — see [LICENSE](LICENSE).
