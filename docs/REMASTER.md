# Remastering an all-in-one image

`tools/remaster-image.sh` bakes GopForge-Live into a **single bootable file** that
auto-launches the wizard — no shell command, no separate bundle copy.

```bash
# on a Linux host / WSL:
./tools/fetch-vendor.sh
./tools/fetch-roms.sh
sudo apt-get install -y dmg2img fatresize gdisk   # dmg convert + FAT grow + GPT
./flash-usb/get-base-image.sh            # downloads the .dmg and converts → raw .img
sudo ./tools/remaster-image.sh --img flash-usb/NOVEMBER_BLUES.img --out flash-usb/gopforge-live.img
# then write gopforge-live.img to a USB. WSL can't see USB sticks, so use the
# Windows writer or balenaEtcher:
#   .\flash-usb\write-image-windows.ps1 -Image .\flash-usb\gopforge-live.img -NoInstall
```

> The GRML-FLASH release asset is a **zlib-compressed `.dmg`**. `losetup` needs a
> raw `.img`, so `get-base-image.sh` and `remaster-image.sh` convert it with
> `dmg2img`. balenaEtcher can write the raw `.dmg` directly if you skip remastering.

## Why the GRML-FLASH `.img`, and why an additive module

- **Mac boot** is the hard part. GRML-FLASH's author already made the image boot
  on classic Mac Pros and 2009–2011 iMacs. Rebuilding a plain GRML ISO from scratch
  risks losing that. So we remaster the GRML-FLASH image **in place** and never touch
  its partition table or boot code.
- GRML uses **live-boot**, which stacks *every* squashfs in the medium's `live/`
  directory as an overlay. Instead of unpacking and resquashing the multi-GB base
  filesystem, we build one small **additive module** `zz-gopforge.squashfs` and drop
  it into `live/`. It overlays these new files onto the running system:
  - `/opt/gopforge-live/…` — the wizard, ROM library, `vendor/gopforge`, and a
    static `bin/jq` (so matrix matching works even if the base OS lacks jq).
  - `/etc/systemd/system/gopforge.service` (+ a `multi-user.target.wants` symlink) —
    launches `bin/autostart.sh` on **tty1**.
  - a `getty@tty1` override so the wizard owns the console.

  The `zz-` prefix makes it sort last, so its overlay wins.

## Prerequisites

Root on Linux, plus `losetup`, `mksquashfs` (`squashfs-tools`), `rsync`, `blkid`,
`mount`. `curl` is used to fetch a static `jq` for the image (optional). Prepare the
checkout first with `fetch-vendor.sh` + `fetch-roms.sh`.

## Options

| flag | meaning |
|------|---------|
| `--img <file>` | the GRML-FLASH base image (required) |
| `--out <file>` | output image (default `<img>-gopforge.img`) |
| `--grow-mb N` | enlarge the output container by N MiB before adding the module (only helps if the FAT partition already has slack) |
| `--comp gzip\|zstd\|xz` | squashfs compressor (default `gzip` for widest live-boot compatibility) |

## Tuning / known-fragile points (verified with GRML-FLASH v2.0.0; other builds may differ)

- **Module inclusion.** If `live/` contains a `filesystem.module`/`*.module` list,
  the script appends `zz-gopforge.squashfs` to it. If live-boot on your GRML build
  ignores un-listed squashfs, make sure that append happened.
- **tty1 ownership.** The systemd service uses `Conflicts=getty@tty1` +
  `StandardInput=tty`. Some builds need `systemctl disable getty@tty1` baked in
  instead; adjust the override if you get a login prompt fighting the wizard.
- **No free space.** `mksquashfs` writes into the mounted FAT partition; if it's
  full, either the base image has no slack (use a larger base, or the ISO path
  below) — `--grow-mb` only helps when the partition can already hold more.
- **Fallback.** Even if autostart doesn't fire, the files are present; boot to a
  shell and run `sudo bash /…/opt/gopforge-live/bin/gopwizard.sh`.

## ISO alternative (PC targets)

If you only need PC boot (not Mac), you can remaster a plain GRML **ISO** with the
standard `unsquashfs` → modify → `mksquashfs` → `xorriso -boot_image any replay`
flow. That path is not scripted here because it tends to break Mac EFI boot, which
is the whole point of starting from GRML-FLASH.
