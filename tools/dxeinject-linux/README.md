# DXEInject for Linux

GopForge patches a Mac Pro 4,1/5,1 BootROM with dosdude1's **DXEInject**, which only
exists as a macOS binary. The GopForge-Live USB runs Linux, so it carries this
replacement instead.

DXEInject is UEFITool's 0.2x `FfsEngine` in a small wrapper. It finds the DXE driver
`BAE7599F-3C6B-43B7-BDF0-9CE07AA91AA6`, inserts the `.ffs` right after it, and rebuilds
the image. [`main.cpp`](main.cpp) does the same operation on the same engine
([UEFITool 0.28.0](https://github.com/LongSoft/UEFITool/tree/0.28.0), BSD-2-Clause).
It uses the same command line, so GopForge calls it with `--dxeinject`:

```
dxeinject <in.rom> <out.rom> <file.ffs>
```

It also refuses things DXEInject doesn't check for:
- a missing or duplicated insertion point (exit 4)
- a driver that's already in the image (exit 7)
- any rebuild that would change the image size (exit 6)

## Build

```bash
sudo tools/dxeinject-linux/build.sh      # needs debootstrap + git; ~5 min the first time
```

This compiles in a Debian **bookworm** chroot, so the binary needs glibc 2.36 or newer,
which GRML-FLASH has. It then writes `vendor/dxeinject-linux/`:
- `dxeinject` (wrapper)
- `dxeinject.bin`
- `lib/`, which holds Qt5Core and its non-glibc dependencies (~47 MB, mostly ICU data)
- the UEFITool license
- `BUILDINFO`

`remaster-image.sh` and `install-to-usb.sh` pick this directory up automatically.

## How it was validated

Tested against Apple's own `MP51.fd` (144.0.0.0.0) from the macOS Mojave 10.14.6
installer:

- **Same as the reference engine.** Output is byte-identical to a UEFITool 0.28
  build on a different distro, for both EnableGop and EnableGopDirect. Running it
  inside GRML-FLASH's own rootfs gives the same bytes.
- **Rebuild without insert returns the original image**, byte for byte.
- **Independent parser.** UEFITool NE (UEFIExtract, a separate codebase) parses the
  patched images with no new warnings and no checksum or CRC errors. Of about 1,100
  items, the only ones that differ are:
  - the new `EnableGop 1.4` file, placed directly after `BAE7599F`
  - the DXE volume's AppleCRC32 and used-space fields (volume size unchanged)
  - the shrunken free space

  Every other file, NVRAM, microcode and the boot block are identical.
- **Changes stay in the DXE volume.** The app also enforces this at patch time and
  before writing: `bootrom_changes_confined` refuses any patched image that differs
  from the backup outside the DXE volume holding the insertion point.

Not yet done: a byte comparison with dosdude1's macOS DXEInject itself. If you have a
dump and the DXEInject/GopForge output made from it on macOS, run
`dxeinject dump.rom out.rom EnableGop.ffs` and `cmp` the result.
