# Recovery — when a flash goes wrong

**Read this before you flash anything.** Both targets this tool writes to are
brickable. Have a recovery path ready *first*.

## GPU vBIOS (amdvbflash / nvflash)

- **Backup exists**: the wizard saves the original to
  `…/gopforge-live/video/Backups/` and verifies it before flashing. Keep it.
- **Bad flash, no display**: put the card in another PC (or use the Mac's iGPU /
  a second GPU), boot GRML-FLASH again, and re-flash the backup:
  - AMD: `amdvbflash -f -p <idx> backup.rom`
  - NVIDIA: `nvflash -i<idx> --protectoff && nvflash -i<idx> -6 backup.rom`
- **Dual-BIOS cards**: flip the BIOS switch to the good position to boot, then
  flash the bad one.
- **Hardware fallback**: a CH341A SPI programmer with a clip can rewrite the
  GPU's SPI EEPROM directly if the card won't POST at all.

## Mac BootROM (flashrom)

This is the higher-stakes target.

- **Backup exists**: the wizard dumps and verifies the original before writing.
  It lives in `…/gopforge-live/firmware/Backups/`. **Copy it off the USB too.**
- **Write failed / interrupted**: do **not** power-cycle mid-write if a re-flash
  can still run. Re-run `flashrom -w backup.rom` to restore the original.
- **Apple SPI lock**: some Macs refuse an in-system write (protected ranges /
  descriptor lock) even though the read worked. If `flashrom -w` fails cleanly
  and the machine still boots, the BootROM is likely unchanged — the write just
  didn't take. Investigate flashrom's log before retrying.
- **Machine won't boot (bricked)**: recover the SPI flash out-of-band with a
  **CH341A** programmer (in-circuit clip or desoldered chip) and write back the
  saved dump. For classic Mac Pro 4,1/5,1 this is the same physical chip a
  "Matt card" / hardware programmer targets. This is why GopForge's docs insist
  on a hardware recovery path before flashing the BootROM.

## General

- Prefer flashing with the machine on stable power (UPS / no risk of power loss).
- Never delete the `Backups/` folder until the new firmware is confirmed good.
- If unsure, stop and ask on the relevant MacRumors thread (EnableGop / iMac GPU
  upgrade) before writing.
