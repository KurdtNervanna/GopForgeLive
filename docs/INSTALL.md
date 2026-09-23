# Installing GopForge-Live

Two paths. Start with **A** (fast to iterate and test); **B** is the eventual
polished image.

## A. Drop onto an existing GRML-FLASH USB (recommended for now)

1. Build a GRML-FLASH USB normally: restore the latest
   [GRML-FLASH release](https://github.com/Ausdauersportler/GRML-FLASH/releases)
   `.img` to a USB/SD with Balena Etcher. It already bundles `flashrom`,
   `amdvbflash`, `nvflash`, `UEFIPatch`, and the EnableGop GCN4 vBIOS set.
2. On a networked machine, populate the vendored tools and the ROM library:
   ```bash
   ./tools/fetch-vendor.sh   # clones GopForge + pre-caches EnableGop.ffs
   ./tools/fetch-roms.sh     # pulls the whole IMAC-EFI-BOOT-SCREEN vBIOS set
   ```
   `fetch-roms.sh` downloads every ROM from
   [Ausdauersportler/IMAC-EFI-BOOT-SCREEN](https://github.com/Ausdauersportler/IMAC-EFI-BOOT-SCREEN)
   (GPL-3.0), unzips the packed ones into `roms/<METHOD>/`, and generates
   `roms/index.json` by reading each vBIOS's PCI device id. These GPL blobs stay
   under `roms/` (fetched, never committed to this MIT repo).
3. The wizard recommends from `catalog/imac-boot-screen-matrix.json`, which encodes
   the upstream model/panel/memory rules. It only ever offers ROMs that are actually
   present under `roms/`.
4. Mount the USB's data/persistence partition and install:
   ```bash
   ./tools/install-to-usb.sh /path/to/mounted/usb
   ```
5. Boot the target Mac from the USB, then in the GRML shell:
   ```bash
   cd <data-partition>/gopforge-live
   sudo bash bin/gopwizard.sh
   ```
   Headless (dead GPU): SSH in as root (GRML-FLASH default password `flash`) and
   run the same command.

## B. Bake it into a custom image (later)

`tools/build-image.sh` is a stub for a `grml2usb` remaster that auto-launches the
wizard on login. Manual outline until it's done:

1. Restore the GRML-FLASH `.img`, mount persistence, run `install-to-usb.sh`.
2. Add an autostart line (e.g. append to the live user's `~/.zlogin`):
   `sudo bash /path/gopforge-live/bin/gopwizard.sh`
3. Rebuild with `grml2usb` per the GRML-FLASH README to persist it.

## Dependencies expected in the live environment

`bash`, `whiptail` (falls back to plain prompts), `pciutils` (`lspci`),
`dmidecode`, `flashrom`, `perl`, `awk`, `jq` (for catalog matching), and the
vendor-supplied `gopforge.sh`. GRML ships most of these; `jq`/`whiptail` may need
`apt-get install` in a networked live session if absent.
