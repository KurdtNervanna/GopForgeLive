# iMac boot-screen ROM matrix schema

`imac-boot-screen-matrix.json` drives GPU vBIOS recommendation. It captures the
decision rules from
[Ausdauersportler/IMAC-EFI-BOOT-SCREEN](https://github.com/Ausdauersportler/IMAC-EFI-BOOT-SCREEN)
so the wizard can turn *(detected iMac model + GPU)* into a ranked, safety-marked
list of the ROMs that upstream ships.

## Top level

| field | meaning |
|-------|---------|
| `matrix_version` | semver of this data |
| `methods` | glossary: `gop`, `eg2`, `eg`, `eg91`, `uga`, `lvds` |
| `model_rules` | per-iMac-model panel/driver constraints (keyed by `dmidecode` product name, e.g. `iMac12,2`) |
| `cards` | GPU entries with their candidate ROMs |

## `model_rules[<model>]`

| field | meaning |
|-------|---------|
| `panel` | `lvds` \| `edp` \| `unknown` |
| `driver` | `eg91` (iMac9,1) \| `eg` \| `any` |
| `forbid_methods` | methods that are broken on this model (e.g. `["eg2"]` on `iMac10,1-A1312`) |
| `ambiguous` | true when `dmidecode` can't distinguish sub-variants (e.g. `iMac10,1` A1311 vs A1312) |
| `note` | shown to the user |

## `cards[]`

| field | meaning |
|-------|---------|
| `name` | human name |
| `match.device` | PCI device ids (lowercase hex) that identify this card |
| `match.name_globs` | substrings matched against the `lspci` name when no device id hits |
| `family` | `GCN1` / `GCN3` / `GCN4-Polaris` / `RDNA1` … |
| `lvds` | whether the card has LVDS signalling (Polaris/GCN4 = false) |
| `memory_variants` | true when ROMs are memory-vendor-specific |
| `hot` | true if it overheats iMac9,1 under load |
| `roms[]` | candidate ROMs |

### `roms[]` entry

| field | meaning |
|-------|---------|
| `file` | path under `roms/` (`EG2/…`, `GOP/…`; packed `.rom.zip` is unzipped to `.rom` by `fetch-roms.sh`) |
| `method` | `gop` \| `eg2` \| `eg` \| `eg91` \| `uga` |
| `panel` | `lvds` when it's the LVDS-panel variant |
| `mem` | memory vendor (`HynixAFR`, `Elpida`, …) — must match the card's VRAM |
| `vram` | `alt` / `4GB` strap variant |
| `note` | free text (e.g. subsystem id) |

## Ranking + safety (`bin/lib/library.sh`)

- Recommendation order: `gop > eg2/eg91 > eg > uga`, then demoted by the model marker.
- Each ROM is marked **✓ suitable / ⚠ caution / ✗ won't work** against the model
  profile (forbidden method, missing LVDS, wrong EnableGop variant, unneeded LVDS ROM).
- Only ROMs actually present in `roms/` are listed. A full-library browser is always
  available as an expert escape hatch.
- The wizard never flashes without a verified backup + explicit confirm; it will *warn*
  on a ✗ but does not hard-block, since edge cases exist.
