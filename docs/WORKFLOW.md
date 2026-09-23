# GopForge-Live workflow

The goal is a **native pre-boot GOP screen** on an EFI-era Mac with a modern GPU.
Getting there can need work on **two** independent targets, and the wizard covers
both:

```
                 ┌─────────────────────────────────────────┐
                 │  Detect: dmidecode (model) + lspci (GPU) │
                 └───────────────┬─────────────────────────┘
                                 │
        ┌────────────────────────┴───────────────────────────┐
        │                                                     │
  ┌─────▼──────────────┐                        ┌─────────────▼─────────────┐
  │ GPU vBIOS branch   │                        │ Mac BootROM branch        │
  │ (amdvbflash/nvflash)│                       │ (flashrom + GopForge)     │
  │                    │                        │                           │
  │ detect card+model  │                        │ dump ROM (flashrom -r)    │
  │ → matrix match     │                        │ → GopForge --check (ID)   │
  │   (✓/⚠/✗ per model)│                        │ → GopForge --inject       │
  │ → backup vBIOS     │                        │                           │
  │ → flash GOP vBIOS  │                        │ → flashrom -w (write back)│
  └────────────────────┘                        └───────────────────────────┘
```

## Which branch do I need?

It depends on where GOP is missing:

| Situation | Fix |
|-----------|-----|
| GPU vBIOS already has GOP (e.g. Vega 64, many Mac-EFI cards) | **BootROM branch only** — inject EnableGop so the Mac's firmware exposes the picker. |
| GPU vBIOS has **no** GOP (Fury/Fiji, many ex-mining/older AMD) | **Both** — burn GOP into the GPU vBIOS *and* inject EnableGop into the BootROM. |
| You only want the GPU flashed (e.g. MXM iMac upgrade) | **GPU vBIOS branch only.** |

## Decisive test (from GopForge's own findings)

After a BootROM EnableGop flash, run OpenCore's `BootKicker.efi`:
- Apple picker appears → GOP plumbing works. If the screen was black before the
  picker, try the **EnableGopDirect** variant.
- Nothing appears at all → the **GPU** has no usable GOP; do the GPU vBIOS branch.

On a non-native GPU a silent boot won't draw the grey Apple logo — **hold ⌥
(Option) at power-on** to get the native picker pre-OpenCore. A monitor that
gets signal at the chime but stays black until the picker is often success, not
failure.

## Safety rules the wizard enforces

- Every write is preceded by a **verified backup** (size + sha256).
- GPU auto-flash is limited to catalog entries marked `verified: true`.
- The BootROM write requires a **double confirmation**.
- GopForge refuses to inject into anything that isn't a MacPro4,1/5,1 image
  (size + insertion-point GUID), so a wrong dump can't be patched.
