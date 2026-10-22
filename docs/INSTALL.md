# Installing GopForge-Live

Every [release](https://github.com/KurdtNervanna/GopForgeLive/releases) has three files:

| File | What it's for |
|---|---|
| `gopforge-live-<version>.img.xz` | **A USB stick** (recommended). Boots straight into the app and keeps backups and the log on the stick. |
| `gopforge-live-<version>.iso` | **A DVD**, burned from Windows, Linux or macOS. |
| `gopforge-live-<version>.dmg` | **The same DVD** as a macOS disk image, for burning on a Mac. |

Check a download against `SHA256SUMS.txt` from the same release.

## A. USB stick (recommended)

1. Write `gopforge-live-<version>.img.xz` to a USB stick of 2 GB or more with
   [balenaEtcher](https://etcher.balena.io/) (Windows / macOS / Linux). Etcher reads the
   `.xz` directly. You can also use `flash-usb/write-image-*.sh` / `.ps1`. This erases the
   stick. If Windows then offers to format the disk, choose **Cancel**.
2. On the Mac, hold **⌥ Option** at power-on and pick **EFI Boot**.
3. The app appears after a short countdown. See [TESTING.md](TESTING.md) for your first run.

## B. DVD

The disc is about 1 GB, so it needs a **DVD±R**. It doesn't fit on a 700 MB CD.

- **Windows:** right-click the `.iso` › **Burn disc image**.
- **Linux:** Brasero / K3b / Xfburn, or `growisofs -dvd-compat -Z /dev/sr0=gopforge-live-<version>.iso`.
- **macOS:** right-click the `.dmg` (or the `.iso`) in Finder › **Burn "…" to Disc**, or
  `hdiutil burn gopforge-live-<version>.dmg`.

Boot it like the stick: hold **⌥ Option**, pick **EFI Boot** (the disc icon).

### A disc can't be written to: Save to USB

A DVD session keeps backups, hardware reports and the log **in memory**, so they'd be
lost at shut-down. To keep them:

1. Plug in a USB drive formatted **FAT32 (MS-DOS)** or **exFAT** (NTFS and Linux drives
   work too; journaled Mac drives can't be written from Linux).
2. Choose **Memory only — Save to USB…** at the bottom of the sidebar (in the text
   wizard: **Save to USB drive**) and pick the drive.
3. Everything is copied into a `gopforge-live` folder on the drive and checked byte for
   byte. From then on new backups and the log go straight to the drive. **Eject** it
   from the same place before unplugging.

**Nothing is flashed while the backups are only in memory.** If a flash goes wrong,
the backup has to survive the restart that follows. The app asks you to save first and
keeps the Flash buttons locked until you have. Expert Mode overrides this.

If the drive already has a `gopforge-live` folder (for example the data partition of a
GopForge-Live stick), the files are merged: identical files are skipped, and the log is
appended. That's also how the **4,1→5,1 Crossflash** finds its `templates.zip` on a DVD
session: put it in `gopforge-live/templates/` on the drive you save to.

## Build the images yourself (Linux or WSL, as root)

One command builds all three release files, the same way the GitHub release workflow
does ([`.github/workflows/release.yml`](../.github/workflows/release.yml)):

```bash
sudo tools/build-release.sh --install-deps      # → dist/*.img.xz, *.iso, *.dmg, SHA256SUMS.txt
```

It fetches GopForge, the ROM library and the pinned GRML-FLASH base image, builds the
Linux injector in a Debian chroot, remasters the USB image, makes the DVD images, and
audits all of them with `tools/release-check.sh` (wrong version, missing pieces, or
anything that must never be published, such as Apple firmware or backups from a test
machine). The individual steps:

```bash
./tools/fetch-vendor.sh                      # GopForge + EnableGop.ffs / EnableGopDirect.ffs
./tools/fetch-roms.sh                        # IMAC-EFI-BOOT-SCREEN vBIOS library (GPL-3.0)
sudo ./tools/dxeinject-linux/build.sh        # Linux DXEInject for Boot ROM patching
./flash-usb/get-base-image.sh                # GRML-FLASH base image
sudo ./tools/remaster-image.sh --img <grml-flash.img> --out gopforge-live.img
sudo ./tools/make-iso.sh --img gopforge-live.img --out gopforge-live.iso [--dmg gopforge-live.dmg]
```

`remaster-image.sh` adds one extra squashfs module to the base image. The module
contains the app, the ROM library, the Linux injector, a static `jq`, and an
auto-start service. It also adds `iomem=relaxed` (flashrom needs it) and a US
keyboard layout to the boot entries. See [REMASTER.md](REMASTER.md).

`make-iso.sh` puts the same files on an EFI-bootable ISO 9660 disc. It uses GRML's own
EFI GRUB from an El Torito image, the layout GRML's official ISOs use. It gives the disc
its own boot ID, so a GopForge-Live stick plugged in at boot can't be mistaken for the
disc, and drops `persistence` from the boot entries. `--dmg` also writes a macOS disk
image of the same disc (needs `dmg` from libdmg-hfsplus; `build-release.sh` builds it).

### Publishing a release

Bump `GFL_VERSION` in `bin/lib/bootstrap.sh` (and the README status), commit, then push
a tag with the same version:

```bash
git tag v0.5.0-beta && git push origin v0.5.0-beta
```

The workflow builds and audits the three files and publishes them as the **Latest**
release, which is what the repository's front page shows under *Releases* (GitHub
doesn't feature pre-releases there). `-alpha`, `-rc` and `-dev` versions become
pre-releases instead. To try the build without publishing, run the
workflow by hand from the Actions tab: the files are kept as a workflow artifact for
7 days, and ticking **draft** also opens a draft release.

## C. Add it to an existing GRML-FLASH USB

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
   all-in-one images. If the Mac has no working display, SSH in as `root` (GRML-FLASH
   password `flash`) and run the same command.

## What the live system needs

- **Base tools:** `bash`, `perl`, `awk`, `pciutils`, `dmidecode`, `flashrom`, `whiptail`.
- **Graphical app:** Xorg, `xinit`, `python3`, `firefox-esr`.

GRML-FLASH ships all of these. The image also brings its own `jq`, plus the Linux
injector with its Qt libraries. When the app can't start, it falls back to the text
wizard, and `whiptail` falls back to plain numbered prompts.
