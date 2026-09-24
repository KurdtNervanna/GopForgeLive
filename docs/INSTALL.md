# Installing GopForge-Live

There are two ways to get GopForge-Live onto a USB stick:

- **Option A: the all-in-one image (recommended).** The stick boots straight into the app.
- **Option B: add it to a GRML-FLASH USB you already have.** You start it yourself
  from a shell.

## A. The all-in-one image

### Write a ready-made image

If you already have `gopforge-live.img` (for example `flash-usb/gopforge-live.img`):

1. Write it to a USB stick of 2 GB or more with [balenaEtcher](https://etcher.balena.io/)
   (Windows / macOS / Linux), or use `flash-usb/write-image-*.sh` / `.ps1`. This
   erases the stick. If Windows then offers to format the disk, choose **Cancel**.
2. On the Mac, hold **⌥ Option** at power-on and pick **EFI Boot**.
3. The app appears after a short countdown. See [TESTING.md](TESTING.md) for your first run.

### Build the image yourself (Linux or WSL, as root)

```bash
./tools/fetch-vendor.sh                      # GopForge + EnableGop.ffs / EnableGopDirect.ffs
./tools/fetch-roms.sh                        # IMAC-EFI-BOOT-SCREEN vBIOS library (GPL-3.0)
sudo ./tools/dxeinject-linux/build.sh        # Linux DXEInject for Boot ROM patching
./flash-usb/get-base-image.sh                # GRML-FLASH base image
sudo ./tools/remaster-image.sh --img <grml-flash.img> --out gopforge-live.img
```

`remaster-image.sh` adds one extra squashfs module to the base image. The module
contains the app, the ROM library, the Linux injector, a static `jq`, and an
auto-start service. It also adds `iomem=relaxed` (flashrom needs it) and a US
keyboard layout to the boot entries. See [REMASTER.md](REMASTER.md).

## B. Add it to an existing GRML-FLASH USB

1. Write the latest
   [GRML-FLASH release](https://github.com/Ausdauersportler/GRML-FLASH/releases) to a USB
   stick. It already includes `flashrom`, `amdvbflash` and `nvflash`.
2. Run the `fetch-*` steps and `dxeinject-linux/build.sh` from above, then:
   ```bash
   ./tools/install-to-usb.sh /path/to/mounted/usb
   ```
3. Boot the Mac from the stick, then in the GRML shell:
   ```bash
   cd <data-partition>/gopforge-live && sudo bash bin/gopwizard.sh
   ```
   This path gives you the text wizard. The graphical app auto-starts only on the
   all-in-one image. If the Mac has no working display, SSH in as `root` (GRML-FLASH
   password `flash`) and run the same command.

## What the live system needs

- **Base tools:** `bash`, `perl`, `awk`, `pciutils`, `dmidecode`, `flashrom`, `whiptail`.
- **Graphical app:** Xorg, `xinit`, `python3`, `firefox-esr`.

GRML-FLASH ships all of these. The image also brings its own `jq`, plus the Linux
injector with its Qt libraries. When the app can't start, it falls back to the text
wizard, and `whiptail` falls back to plain numbered prompts.
