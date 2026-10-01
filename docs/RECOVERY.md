# Recovery: when a flash goes wrong

**Read this before you flash anything.** Both kinds of chip this tool writes to can be
bricked, so have a way back ready *first*.

## Built into the app

- **Backups come first.** Nothing is flashed until a backup of that exact chip or card
  is saved to the USB and checked. The backups live in
  `gopforge-live/firmware/Backups/` (Boot ROM) and `gopforge-live/video/Backups/`
  (graphics firmware). **Copy them off the USB as well.**
- **Backups › Restore** writes a backup back:
  - **Boot ROM:** you type `RESTORE BOOTROM`. The chip is read first. Normally the
    restore is only allowed if the chip matches the backup everywhere outside the DXE
    driver volume, meaning it's the same Mac with a patch added since. An older backup,
    or one from another Mac, would roll back NVRAM or change the serial, so it needs
    Expert Mode.
  - **Graphics firmware:** you type `RESTORE`. The backup can only go back onto the
    card it was read from.
- **Stale-backup check.** Just before a Boot ROM write, the chip is read again and must
  still match your backup byte for byte. If it changed (the firmware writes NVRAM),
  nothing is written, and you're asked to back up and patch again.

## Graphics firmware (amdvbflash / nvflash)

- **Bad flash, but the Mac still boots:** boot this USB and use **Backups › Restore**.
  If the internal display is dark, use an external display, or run the command below
  over SSH.
- **No display at all:** put the card in another computer (or use a second GPU), boot
  GRML-FLASH, and flash the backup back:
  - AMD: `amdvbflash -f -p <idx> backup.rom`
  - NVIDIA: `nvflash -i<idx> --protectoff && nvflash -i<idx> -6 backup.rom`
- **Dual-BIOS cards:** flip the switch to the good BIOS to boot, then flash the bad one.
- **Card won't POST at all:** a CH341A SPI programmer with a clip can rewrite the card's
  EEPROM directly.

## Mac Boot ROM (flashrom)

This is the riskier of the two.

- **The write failed or was interrupted:** **don't power off** while you still have a
  running system. Retry the flash, or use **Backups › Restore**. From a shell, the same
  thing is `flashrom -p internal -w <backup.rom>`.
- **Write protection (flash mode):** at every normal start a Mac Pro marks the Boot ROM
  read-only above `0x150000`. flashrom logs `SPI Configuration is locked down` and
  `PR1: … is read-only`. The app reads this and refuses to flash or restore until you
  restart in **flash mode**: shut down, hold the power button until the Mac beeps, then
  boot the USB. If a write still fails cleanly and the Mac boots, the Boot ROM is most
  likely unchanged. Read the log under **Activity** before retrying.
- **Boots, but no boot screen:** EnableGop is harmless when it isn't working. Try the
  Direct variant (restore, then patch with Direct), or give the GPU GOP firmware.
- **The Mac won't start (bricked):** reprogram the SPI flash from outside with a
  **CH341A** programmer (clip in-circuit, or desolder the chip) and write back your saved
  backup. That's why a hardware recovery path should exist before you flash the Boot ROM.

## General

- Flash only on stable power (a UPS if you have one).
- Keep the `Backups/` folders until the new firmware has proven itself.
- When unsure, ask in the relevant MacRumors thread (EnableGop / iMac GPU upgrade) before
  writing anything.
