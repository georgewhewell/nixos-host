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

## PSB register-write records

The indexed PSB block is a sequence of 8-byte records:

| Record offset | Size | Meaning |
|---:|---:|---|
| `+0x0` | 4 | register value |
| `+0x4` | 4 | encoded register descriptor |

The descriptor layout reproduced from the vendor editor is:

| Bits | Meaning |
|---:|---|
| 19:0 | register byte offset divided by four |
| 23:20 | reserved |
| 27:24 | per-byte write mask |
| 28 | broadcast write |
| 31:29 | reserved |

Thus `register_offset = (descriptor & 0x000fffff) << 2`. `pexctl` preserves
the descriptor, reports its reserved bits, and refuses a PSB whose size is not
a multiple of eight or exceeds the Atlas `0x2000`-byte limit. Observed offsets
that resolve in the Atlas register database also receive a stable
`register_key` and a descriptive `register_name`; an unknown offset remains
explicitly unnamed.

## PSB-SerDes AXI-write records

The indexed PSB-SerDes block is also a sequence of 8-byte records, but its
order is address followed by value:

| Record offset | Size | Meaning |
|---:|---:|---|
| `+0x0` | 4 | AXI address |
| `+0x4` | 4 | register value |

When `(address & 0x70000000) == 0x70000000`, bits 25:24 encode the vendor
broadcast mode: 0 none, 1 lane, 2 station, and 3 lane plus station. The address
is retained exactly, including those bits. Other addresses do not carry an
applicable broadcast mode. The block must be a multiple of eight bytes and no
larger than the Atlas `0x4000`-byte limit.

`inspect --json` includes both decoded entry arrays plus the raw dwords and
SHA-256 of every enabled indexed block. `sbr entries` provides a focused human
or JSON view. Known non-reserved PSB records report an `expert` write policy;
unknown and reserved records remain `read-only`.

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
numeric value, and `write_policy`. A policy of `ordinary` means the field has
a typed configuration member. A policy of `expert` means its position is known
but its board constraints and reset behavior have not been independently
validated. The compatibility `writable` boolean is true only for `ordinary`
fields; expert access always requires the separate acknowledgement below.

Expert fields can be changed by exact name through `expert_soc_fields`. Each
patch includes a mandatory `expected` value and is rejected unless the caller
also passes `--allow-expert-fields`. All expected values are checked against
the original input before any field is changed. This supplies access without
misrepresenting a vendor field name as evidence that an arbitrary board value
is safe.

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
or unclassified layouts. Expert fields are omitted from exported editable
configuration and must always be added deliberately. Expert PSB and
PSB-SerDes patches are also omitted.

`expert_psb_entries` changes only the value dword of an existing PSB record.
Each patch requires the record index, known non-reserved register key, exact
expected descriptor, exact expected value, and replacement value. The
descriptor must resolve to the keyed register, and changed bytes must be
selected by its four-bit byte mask.

`expert_psb_serdes_entries` similarly changes only an existing AXI record's
value and requires its index, exact expected address, exact expected value,
and replacement value. Neither form can modify record identity, descriptor,
address, ordering, count, or block size. All identities and expected values
are checked against the original input before any field or entry is changed.
They require `--allow-expert-entries`, independently of the
`--allow-expert-fields` acknowledgement for named SoC fields.
`sbr export-entry-patch` can generate either form from an existing record so
the identity and expected-current fields are not transcribed by hand.

The parser rejects unknown JSON members. Applying a configuration:

1. validates the input image and configuration;
2. changes only typed/named bit fields or explicitly identified expert record
   value dwords;
3. recalculates the checksum;
4. validates the candidate;
5. refuses to overwrite an existing output path.

The full 22-dword index and 104-dword SoC block are present in
`inspect --json` for differential research without claiming that their
remaining values are understood.

## Configuration-plan contract

`device prepare-config` and `device prepare-station` emit a strict
`pexctl.atlas-config-plan.v1` document as `PLAN.json`. It binds the plan to:

- the normalized PCI BDF, PCI identity, and JEDEC identity;
- the supported flash geometry and fixed SBR offset;
- the ordinary and expert apply-policy acknowledgements;
- exactly eleven named artifacts, in canonical order, with their byte lengths and
  lowercase SHA-256 values;
- the device-bound hardware-write confirmation phrase; and
- `hardware_written: false`.

`plan verify` rejects unknown manifest members, extra, missing, or reordered
artifact records, noncanonical hashes, unexpected binary sizes, oversized JSON
artifacts, symlinked directories or files, and any digest mismatch. It then
checks relationships that hashes alone cannot prove: both full-flash reads
must match; the saved current region must be their exact prefix; both saved
SBRs must match their containing regions; the candidate region may differ
only within the fixed-size SBR; applying the canonical saved configuration
with the recorded policy must reproduce the candidate exactly; and the two
inspection documents and diff must regenerate byte-for-byte.

`device program-plan` retains the verified current and candidate recovery
regions in memory, checks the requested live BDF and PCI identity against the
plan, requires the recorded expert acknowledgements again, and passes those
same bytes to the recovery-gated hardware writer. The writer rejects any
candidate difference beyond the one 64 KiB erase block that it programs. A
later file substitution therefore cannot change the bytes selected for the
write. `PLAN.json` does not hash itself; its strict schema and the artifact
relationships are the root of verification. A plan is not cryptographically
signed: its hashes prove internal consistency, not authorship. The exact live
current-region match and explicit device-bound confirmation remain mandatory.

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
