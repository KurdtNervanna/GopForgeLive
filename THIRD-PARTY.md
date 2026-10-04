# Third-party components

GopForge-Live's own code is MIT-licensed (see [LICENSE](LICENSE)). The release disk image
also bundles the following, each under its own license.

| Component | Where | License |
|---|---|---|
| [GRML-FLASH](https://github.com/Ausdauersportler/GRML-FLASH) (the live Linux base image, including `flashrom`, `amdvbflash` and `nvflash` as shipped by that project) | the image itself | per component, as distributed by GRML-FLASH / [grml.org](https://grml.org) |
| [IMAC-EFI-BOOT-SCREEN](https://github.com/Ausdauersportler/IMAC-EFI-BOOT-SCREEN) vBIOS library | `roms/` | GPL-3.0 (`roms/UPSTREAM-LICENSE`, `roms/UPSTREAM-NOTICE.txt`) |
| [GopForge](https://github.com/KurdtNervanna/GopForge) | `vendor/gopforge/` | MIT |
| EnableGop / EnableGopDirect drivers from [OpenCore](https://github.com/acidanthera/OpenCorePkg) | `vendor/gopforge/tools/*.ffs` | BSD-3-Clause |
| [UEFITool 0.28.0](https://github.com/LongSoft/UEFITool/tree/0.28.0) engine (the Linux EnableGop injector) | `vendor/dxeinject-linux/` | BSD-2-Clause (`LICENSE-UEFITool.md`) |
| Qt 5 Core, ICU, PCRE2, double-conversion, GLib, zlib, zstd, libstdc++/libgcc (Debian bookworm builds, bundled for the injector) | `vendor/dxeinject-linux/lib/` | LGPL-3 (Qt) and others; license texts in `vendor/dxeinject-linux/licenses/`, sources at [sources.debian.org](https://sources.debian.org/) |
| [jq](https://jqlang.org/) (static build) | `bin/jq` | MIT |
| [Inter](https://rsms.me/inter/) and [JetBrains Mono](https://www.jetbrains.com/lp/mono/) fonts | `gui/static/fonts/` | SIL Open Font License 1.1 |

**Not included:** dosdude1's macOS `DXEInject` (GopForge-Live uses the Linux build of the
same engine instead), any Apple firmware, and the 144.0.0.0.0 Boot ROM templates used by
**Firmware Update**. You copy Borowski's `templates.zip` from the
[MacRumors guide](https://forums.macrumors.com/threads/guide-how-to-rebuild-update-mac-pro-4-1-5-1-bootrom-with-template-files.2437082/)
to the USB yourself.

Not affiliated with Apple, AMD, NVIDIA, or the projects above.
