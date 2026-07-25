# Atlas SBR format notes

This document records only facts reproduced from a valid PEX88096 image,
Broadcom's distributed PEX88096 RDK image or field database, and independently
published PEX88096 material. It deliberately does not transplant PEX86xx or
PEX87xx EEPROM encodings.

## Container

All integers are little-endian.

| Offset | Size | Meaning |
|---:|---:|---|
| `0x000` | 4 | PEX88096 signature `0xc0103dc4` |
| `0x004` | 88 | 22-dword block index |
| `0x05c` | `0x1a0` | SoC settings |
| indexed | variable | PSB, per-station PSW, PSWx2, and PSB SerDes blocks |
| final dword | 4 | hardware checksum in the low byte |

The index consists primarily of offset/size pairs. Entries 14 and 15 are
reserved in the observed Atlas database; entries 20 and 21 follow the known
block pairs but remain uninterpreted. `pexctl` derives the image end from the
largest enabled block end, then expects the checksum dword immediately after
it. Ignored blocks use offset zero with a nonzero size.

The checksum is:

```text
checksum = 0 - (0xa5 + sum(all bytes before the checksum dword)) mod 256
```

The remaining three bytes of the checksum dword are zero in the observed
images. Mutation rewrites the complete dword with the calculated low byte.

## First SoC dword

The SoC block begins at SBR offset `0x5c`.

| Bits | JSON field | Interpretation | Writable |
|---:|---|---|---|
| 7:0 | `soc.upstream_port` | upstream port number | yes |
| 9:8 | `soc.max_link_speed` | `0` Gen1, `1` Gen2, `2` Gen3, `3` Gen4 | yes |
| 12:10 | — | reserved | no |
| 15:13 | `soc.lane_enable_code_raw` | vendor-named lane-enable field; value semantics unknown | no |
| 87:16 | `stations[*].codes` | 24 packed 3-bit quarter codes | only proven layouts |

The six stations consume four consecutive quarter codes apiece. The bit stream
crosses dword and byte boundaries; it must not be treated as six independent
station-wide three-bit values.

## Additional named fields

`inspect --json` decodes the field positions whose names are present in the
Atlas field database at SBR offsets `0x68`, `0x6c`, and `0x70`. These include
station DPR enablement, Atlas mode, automatic PCIe link training, fanout and
STP controls, station clock controls, hot-plug and power controls, secure boot,
watchdog, SPI ECC, and boot-ROM/RAM ECC controls.

They appear under `soc.named_fields` with their SBR offset, low/high bit,
numeric value, and write-support flag. These are read-only: a field name and
bit width establish how to inspect a value, but do not establish the board
constraints or reset behavior needed to mutate it safely.

## Proven station codes

| Quarter codes | Classification | Evidence |
|---|---|---|
| `[0,0,0,0]` | x16 | live PEX88096 and published all-x16 Device Editor image |
| `[1,1,1,1]` | x4+x4+x4+x4 | Broadcom PEX88096 RDK fan-out stations |
| `7` in a quarter | disabled quarter | unused quarters in the same RDK image |

Code 7 is exposed as raw evidence, not yet as a writable layout. The RDK also
contains `[1,1,7,7]`, which supports per-quarter disable semantics but does not
establish every possible mixed layout. No x8 or x8+x4+x4 write encoding is
claimed yet.

## Configuration contract

`pexctl.atlas-config.v1` is a patch, not a complete reserialization of the
binary format. Omitted fields and stations are unchanged. A station entry with
no `layout` is also unchanged; this permits an exported file to preserve raw
or unclassified layouts.

The parser rejects unknown JSON members. Applying a configuration:

1. validates the input image and configuration;
2. changes only named bit fields;
3. recalculates the checksum;
4. validates the candidate;
5. refuses to overwrite an existing output path.

The full 22-dword index and 104-dword SoC block are present in
`inspect --json` for differential research without claiming that their
remaining values are understood.

## Evidence boundary

- [Broadcom's SDK page](https://www.broadcom.com/products/pcie-switches-retimers/software-dev-kits)
  identifies PEX Device Editor as the vendor configuration interface.
- The
  [open PEX88096 baseboard project](https://oshwhub.com/eda_nrhnxjzuv/pex88096-pcie4-switch-gpu-basepl)
  publishes an all-x16 Device Editor view and configured SBR attachments.
- [`PRIOR-ART.md`](PRIOR-ART.md) records related tools and why older
  `0x5a`-stream EEPROM material is not used as Atlas format evidence.

Vendor database names and bit boundaries were independently tested against
the live SBR bytes. Proprietary documentation and RDK binaries are not copied
into this repository.
