# First run on real hardware

GopForge-Live has been checked in QEMU, against simulated hardware, and against Apple's
own `MP51.fd` (144.0.0.0.0). This checklist takes a real Mac from read-only steps to a
flash, one stage at a time. **Stop at any stage that doesn't look right.**

## Mac Pro 4,1 / 5,1

**Stage 1: read-only (safe).**

1. Boot the USB: hold ⌥ Option, pick **EFI Boot**.
2. **Overview:** the Mac shows as *Mac Pro (MacPro5,1)*. A 4,1 flashed to 5,1 also shows
   as 5,1, which is correct. Check the tool list:
   - flashrom: *Available*
   - EnableGop drivers: *Standard + Direct cached*
   - EnableGop injector: *Ready*
3. **Add GOP cMP › Back Up Boot ROM.** The backup should be **4,194,304 bytes**, and all four
   Inspect checks should be green.

**Stage 2: patch (still safe).** This only writes a new file to the USB.

4. Choose **Standard**, then **Create Patched Image**. The Activity log should show
   *changes confined to the DXE volume at 0x150000*.
5. Shut down and send back:
   - `gopforge-live/gopforge-live.log`
   - the two `.rom` files in `gopforge-live/firmware/Backups/` (they contain your serial
     number, so share them only if you're comfortable)

   These are checked offline with UEFITool NE before stage 3.

**Stage 3: flash.** Do this only once stage 2 has been reviewed, and with a CH341A on hand.

A Mac Pro write-protects the Boot ROM region EnableGop goes into at every normal start.
flashrom reports this as `PR1: 0x00150000-0x01ffffff is read-only`, and the app shows
*Restart in flash mode to write*. So:

6. Shut down. Press and hold the power button until the Mac **beeps** (the power light
   flashes), then let go. As it starts, hold ⌥ Option and pick **EFI Boot**.
7. In that session: **Back Up Boot ROM → Create Patched Image → Flash Boot ROM…**. A
   fresh backup is needed because NVRAM changes on every start. The chip is re-read first,
   and if it is still locked or changed since the backup, nothing is written.
8. Shut down completely. Power on holding ⌥ Option: the startup picker should appear on
   your graphics card.

If Inspect says **EnableGop is already installed**, this Mac was patched before (for
example with GopForge on macOS), and there's nothing to do.

## 4,1→5,1 Crossflash (and 5,1 rebuild)

This is experimental. It rewrites the whole chip, so treat it like stage 3 above: flash
mode, a CH341A on hand, and a backup copied off the USB.

1. Copy `templates.zip` from the
   [template guide](https://forums.macrumors.com/threads/guide-how-to-rebuild-update-mac-pro-4-1-5-1-bootrom-with-template-files.2437082/)
   into `gopforge-live/templates/` on the USB.
2. Boot the USB in flash mode, then open **4,1→5,1 Crossflash** and choose **Back Up**. The
   Build step shows the current firmware, serial number and LBSN taken from your backup.
3. **Build Firmware Image.** Every check on the Flash step must pass.
4. **First test it without writing.** Send back the log, the backup and the `-144` image.
   Rebuilding an existing 5,1 should reproduce your current ROM everywhere except the
   emptied NVRAM, the template's Fsys/Gaid stores and the checksums and build stamp of
   the last volume (confirmed on a real 5,1).
5. Only then write it. A 4,1 needs Expert Mode, because the 4,1 path hasn't been verified on
   real hardware yet.

## iMac 2009–2011 (GPU firmware)

1. **Overview** shows the right iMac model. For iMac10,1 you'll be asked for the 21.5"
   or 27" version.
2. **Graphics Card:** the right card is preselected, and the recommended firmware
   matches your display and VRAM.
3. **Back Up Card Firmware.** Stop here for the first run, and send back the log and
   the backup file's size.

## If something goes wrong

- If the app doesn't come up, create an empty file named `gopforge-tui` at the top level
  of the USB to get the text wizard. You can also press Ctrl-C during the countdown for
  a shell.
- Logs: `gopforge-live/gopforge-live.log` on the USB. If X fails, also look in
  `/run/gopforge-gui/`.
- **Overview › Full Hardware Report** saves `gopforge-live/reports/hardware-*.txt`
  (CPUs, memory, PCI/USB, Wi-Fi, disks). It includes serial numbers and MAC addresses.
- If the app fills only part of the screen, add `gfl.window=1920x1080` (your screen
  size) to the boot line.
- See [RECOVERY.md](RECOVERY.md).
