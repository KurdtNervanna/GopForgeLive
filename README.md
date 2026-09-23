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
flash-usb/              # Windows/macOS/Linux USB writers + base-image fetcher
vendor/gopforge/        # populated by tools/fetch-vendor.sh (not committed)
roms/                   # full IMAC-EFI-BOOT-SCREEN vBIOS library (GPL-3.0, fetched, not committed)
```

## Make the bootable USB (Windows / macOS / Linux)

```bash
./tools/fetch-vendor.sh                 # GopForge + EnableGop tooling
./tools/fetch-roms.sh                   # the whole IMAC-EFI-BOOT-SCREEN vBIOS library
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

## Boot the target machine

Power on the Mac holding **⌥ Option**, pick the USB, then `sudo bash bin/gopwizard.sh`.
The wizard **detects the machine and offers only what applies**:

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
