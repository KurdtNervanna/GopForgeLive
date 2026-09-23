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
bin/lib/                # ui, detect, catalog, vbios, bootrom, safety
catalog/                # gpu-gop-catalog.json + SCHEMA.md (verified-only auto-flash)
docs/                   # WORKFLOW / INSTALL / RECOVERY
tools/                  # fetch-vendor, install-to-usb, build-image (stub)
vendor/gopforge/        # populated by tools/fetch-vendor.sh (not committed)
roms/                   # EnableGop GCN4 vBIOS drop (not committed)
```

## Quick start

```bash
./tools/fetch-vendor.sh                 # pull GopForge + EnableGop tooling
./tools/install-to-usb.sh /mnt/usb      # onto a GRML-FLASH USB's data partition
# boot the Mac from that USB, then:
sudo bash bin/gopwizard.sh
```

See [docs/INSTALL.md](docs/INSTALL.md) for the full setup and
[docs/WORKFLOW.md](docs/WORKFLOW.md) for which branch (GPU vs BootROM) you need.

## Safety model

- Every hardware write is preceded by a **verified backup** (size + sha256).
- GPU **auto-flash is limited to catalog entries marked `verified: true`** — the
  seed catalog is entirely unverified on purpose, so nothing auto-flashes until a
  human confirms a board on real hardware.
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
