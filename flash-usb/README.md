# Making the bootable USB (Windows / macOS / Linux)

The bootable OS is **GRML-FLASH** (already contains `flashrom`, `amdvbflash`,
`nvflash`). "Flashing the USB" = write that image to a stick, then copy the
GopForge-Live bundle (wizard + ROM library) onto its FAT data partition. The
scripts here do both.

> ⚠️ These writers are **untested** and **destructive** — they erase the target
> disk. Double-check the device every time. If you'd rather use a GUI, write the
> image with **balenaEtcher** or **Rufus**, then copy the bundle manually (below).

## 0. Prepare the bundle (once, on any machine with bash)

```bash
./tools/fetch-vendor.sh    # GopForge + EnableGop tooling
./tools/fetch-roms.sh      # the full IMAC-EFI-BOOT-SCREEN vBIOS library
```

## 1. Get the base image

```bash
./flash-usb/get-base-image.sh          # Linux/macOS/WSL — grabs latest GRML-FLASH
```
On plain Windows, download the image from the
[GRML-FLASH releases](https://github.com/Ausdauersportler/GRML-FLASH/releases) page.

## 2. Write the USB

**Linux**
```bash
sudo ./flash-usb/write-image-linux.sh <image.img> /dev/sdX
```

**macOS**
```bash
sudo ./flash-usb/write-image-macos.sh <image.img> /dev/diskN
```

**Windows** (elevated / Administrator PowerShell)
```powershell
.\flash-usb\write-image-windows.ps1 -Image C:\path\grml-flash.img
```

Each script lists removable/USB disks, makes you confirm the exact target, writes
the image, then copies `gopforge-live/` onto the FAT partition. Pass `--no-install`
(`-NoInstall` on Windows) to only write the image.

## 3. Boot the target Mac

Plug the USB into the Mac, power on holding **⌥ Option**, pick the USB. In the
GRML shell:
```bash
cd /path/to/data-partition/gopforge-live && sudo bash bin/gopwizard.sh
```
The wizard detects the machine and offers only what applies:

| Machine | Offered |
|---------|---------|
| Mac Pro 5,1 / 4,1 | BootROM EnableGop (dump → GopForge → flash). No GPU flash. |
| Supported iMac (2009–2011) | Guided GPU vBIOS flashing. No BootROM path. |
| Mac Pro 3,1 & earlier, other models, non-Apple | Nothing (Expert override available). |

## Manual bundle copy (GUI-written USB)

After writing the image with Etcher/Rufus, the FAT partition mounts on your
computer. Copy the repo's `bin/`, `catalog/`, `docs/`, `roms/`, and
`vendor/gopforge/` into a `gopforge-live/` folder on it — or, from Linux/macOS,
run `tools/install-to-usb.sh <mountpoint>`.
