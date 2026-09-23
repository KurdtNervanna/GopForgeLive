# GPU GOP vBIOS catalog schema

`gpu-gop-catalog.json` maps a detected GPU to a known-good, GOP-enabled vBIOS.

## Top level

| field | type | meaning |
|-------|------|---------|
| `catalog_version` | string | semver of the catalog data |
| `updated` | string | ISO date of last edit |
| `note` | string | free text |
| `cards` | array | list of card entries |

## Card entry

| field | type | required | meaning |
|-------|------|----------|---------|
| `name` | string | yes | human-readable card name |
| `vendor` | string | yes | PCI vendor id, lowercase hex, no `0x` (`1002` AMD, `10de` NVIDIA) |
| `device` | string | yes | PCI device id, lowercase hex |
| `subsystems` | array<string> | no | list of `svid:sdid` subsystem ids that pin this exact board; empty = matches any subsystem for the device id |
| `family` | string | no | e.g. `GCN4-Polaris` |
| `rom` | string | yes | ROM filename resolved against the ROM search paths (`roms/`, USB `video/`) |
| `verified` | boolean | yes | **only `true` entries are auto-recommended and offered for auto-flash** |
| `notes` | string | no | caveats, strap/memory warnings, provenance |

## Matching rules (see `bin/lib/catalog.sh`)

1. Exact match on `vendor` + `device` **and** the card's `svid:sdid` present in `subsystems`.
2. Fallback: `vendor` + `device` only (looser; caller treats as lower confidence).

## Safety contract

- A card with a shared device id (e.g. Ellesmere `67df` covering RX 470/480/570/580/590)
  MUST use `subsystems` to disambiguate before it is marked `verified: true`.
- Never set `verified: true` from a datasheet alone. Flash, boot, and confirm on the
  actual board first, then record the working `svid:sdid` in `subsystems`.
