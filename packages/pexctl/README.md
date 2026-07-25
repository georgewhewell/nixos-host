# pexctl

`pexctl` is an open, command-line replacement for the configuration parts of
Broadcom's PLX SDK and PEX Device Editor. The initial target is the Atlas
PEX88000 family, tested against a PEX88096.

See [`PRIOR-ART.md`](PRIOR-ART.md) for the surveyed open projects, SDK source
mirrors, hardware projects, and field reports, including the boundary between
older PLX EEPROM formats and Atlas SBR.

The design is deliberately recovery-first:

- parse every image losslessly and preserve unknown bytes;
- derive image length from the SBR index instead of a reference filename;
- validate all block ranges, fixed-region and block overlap, exact known
  sizes, reserved bits, and the hardware checksum before mutation;
- expose only field encodings supported by observed hardware and reference
  images;
- write candidates to new files and refuse accidental overwrites;
- never write hardware until complete-sector preservation and read-back
  verification are available.

## Current commands

```console
pexctl sbr inspect IMAGE
pexctl sbr inspect IMAGE --json
pexctl sbr validate IMAGE
pexctl sbr fields IMAGE
pexctl sbr fields IMAGE --json
pexctl sbr entries IMAGE
pexctl sbr entries IMAGE --block psb-serdes --json
pexctl sbr psw IMAGE
pexctl sbr psw IMAGE --block psw4 --json
pexctl sbr ports IMAGE
pexctl sbr ports IMAGE --port 64 --json
pexctl sbr export-field-patch IMAGE --field soc.customer_scratch1 \
  --value 1 --output expert-field.json
pexctl sbr export-entry-patch IMAGE --block psb --index 0 \
  --value 0x06042018 --output expert-entry.json
pexctl sbr diff BEFORE AFTER
pexctl sbr diff BEFORE AFTER --json
pexctl sbr export-config IMAGE --output config.json
pexctl sbr apply-config IMAGE config.json --output candidate.bin
pexctl sbr apply-config IMAGE expert-config.json --output candidate.bin \
  --allow-expert-fields
pexctl sbr apply-config IMAGE expert-entry.json --output candidate.bin \
  --allow-expert-entries
pexctl sbr set-station INPUT --station 4 --layout x4x4x4x4 --output candidate.bin
pexctl sbr repair-checksum INPUT --output repaired.bin

pexctl flash extract-sbr flash.bin --output current.bin
pexctl flash replace-sbr flash.bin candidate.bin --output candidate-flash.bin

pexctl plan verify config-plan
pexctl plan verify config-plan --json

sudo pexctl device read-sbr --bdf 0000:c4:00.0 --output current.bin
sudo pexctl device inspect-sbr --bdf 0000:c4:00.0 --json
sudo pexctl device fields --bdf 0000:c4:00.0 --json
sudo pexctl device entries --bdf 0000:c4:00.0 --block psb
sudo pexctl device psw --bdf 0000:c4:00.0 --block psw4
sudo pexctl device ports --bdf 0000:c4:00.0 --port 64
sudo pexctl device read-flash --bdf 0000:c4:00.0 \
  --offset 0 --size 0x40000 --output sector-0.bin
sudo pexctl device read-flash --bdf 0000:c4:00.0 \
  --offset 0 --size 0x40000 --method serial --output sector-0-serial.bin
sudo pexctl device spi-id --bdf 0000:c4:00.0
sudo pexctl device flash-status --bdf 0000:c4:00.0 --json
sudo pexctl device backup-flash --bdf 0000:c4:00.0 \
  --output complete-cs0.bin
sudo pexctl device prepare-station --bdf 0000:c4:00.0 \
  --station 4 --layout x4x4x4x4 --output-dir station4-plan
sudo pexctl device prepare-config --bdf 0000:c4:00.0 \
  --config config.json --output-dir config-plan
sudo pexctl device prepare-config --bdf 0000:c4:00.0 \
  --config expert-config.json --output-dir expert-plan --allow-expert-fields
sudo pexctl device prepare-config --bdf 0000:c4:00.0 \
  --config expert-entry.json --output-dir expert-entry-plan \
  --allow-expert-entries

sudo pexctl device program-plan --bdf 0000:c4:00.0 \
  --plan-dir config-plan \
  --confirm ERASE-PROGRAM-VERIFY:0000:c4:00.0:CS0:SECTOR0

sudo pexctl device program-sector0 --bdf 0000:c4:00.0 \
  --expected-current sector-0.bin --candidate candidate-sector-0.bin \
  --confirm ERASE-PROGRAM-VERIFY:0000:c4:00.0:CS0:SECTOR0
```

`inspect --json` is a lossless research view: it includes the 22 raw index
dwords, all 104 raw SoC-setting dwords, every indexed block as raw dwords with
its SHA-256, checksum state, raw station codes, and the stable v1 named-field
set. It also decodes the PSB register-write records and PSB-SerDes AXI-write
records described below. `sbr entries` prints the indexed write records
directly and can select either block with `--block`. `sbr psw` prints the
station/lane PSW view and can select `psw0` through `psw5`, or `pswx2`.
`sbr ports` prints the database-defined port-type and clock-mode tables.
`diff --json` provides hashes, named-field changes, station changes,
PSB/PSB-SerDes entry-value changes, and byte changes.

`sbr fields --json` and `device fields --json` provide the complete current
named-field catalog as `pexctl.atlas-soc-field-inspection.v1`. It contains the
field name, SBR offset, exact bit range, current numeric value, and write
policy. The focused schema can grow independently while the original full
inspection stays byte-compatible with existing `atlas-config-plan.v1`
artifacts.

`export-config` creates the strict, versioned subset that `pexctl` knows how to
write:

```json
{
  "schema": "pexctl.atlas-config.v1",
  "soc": {
    "upstream_port": 0,
    "max_link_speed": "gen4"
  },
  "stations": [
    {
      "station": 4,
      "layout": "x4x4x4x4"
    }
  ]
}
```

Every member is optional except `schema`; at least one writable value is
required. Unknown members, duplicate stations, out-of-range stations, and
unknown enum values are rejected. An exported station whose quarter codes do
not match a proven layout has no `layout` member, so applying the exported file
preserves that station. See
[`examples/station4-x4x4x4x4.json`](examples/station4-x4x4x4x4.json) and
[`FORMAT.md`](FORMAT.md).

Named fields whose positions are understood but whose board behavior has not
been independently validated can be changed through an explicit expert patch:

```json
{
  "schema": "pexctl.atlas-config.v1",
  "expert_soc_fields": [
    {
      "field": "soc.fanout_enable",
      "expected": 0,
      "value": 1
    }
  ]
}
```

Both `apply-config` and `prepare-config` refuse this document unless
`--allow-expert-fields` is present. Each patch must name a field reported with
an `expert` policy by `sbr fields`, and `expected` must exactly match the input
image before any mutation occurs. Unknown fields, duplicate fields, values
wider than the field, and attempts to bypass ordinary typed settings are
rejected.

The catalog includes clock-source/divider, serial-debug, CPU-address,
IOP-reset, system-counter, capture-clock, baud-clock, DCSG scratch and
configuration, customer-scratch fields at SBR offsets `0x6c` through `0x74`,
and three PVTMON pulse-count/ring-select fields at `0x140`. Their bit positions
and vendor names are known; their reset and board behavior are not
independently characterized, so every one remains expert policy. Vendor spare
and reserved fields remain absent. The example is in
[`examples/expert-fanout-enable.json`](examples/expert-fanout-enable.json);
it demonstrates the syntax and is not a recommendation to enable fanout on
this board.

`export-field-patch` constructs the expert document from an existing image. It
fills in the exact current value, checks the requested value against the field
width, and rejects unknown fields, ordinary typed fields, and no-op requests.
Generating a document does not make its replacement value safe; applying or
preparing it still requires `--allow-expert-fields`.

The device reader accesses the Atlas CS0 memory-mapped flash window through the
open PlxSvc ioctl ABI from Broadcom's dual-BSD/GPL SDK. It verifies the PCI
address and device identity against sysfs and PlxSvc independently, checks the
driver ABI version, derives the SBR length from its index, and validates the
resulting checksum. Mapped reads issue only register-read ioctls. Serial reads
drive the Atlas manual-SPI controller registers and issue only JEDEC-ID and
read commands; they do not issue flash write-enable, erase, page-program, PEX
reset, or host reset operations.

`device flash-status` is the read-only protection preflight for the supported
Winbond `EF 60 18` flash. It reads Status Registers 1–3 and, when WPS selects
individual block locks, reads the lock bit for address zero. Its JSON uses the
`pexctl.spi-flash-status.v1` schema. The report includes BUSY, WEL, BP, TB,
SEC, SRP, SRL, CMP, suspend and WPS state plus the raw status bytes.

`device inspect-sbr`, `device fields`, `device entries`, `device psw`, and
`device ports` provide the same focused views directly from the live mapped
CS0 SBR, without first creating an intermediate image. They perform only
PlxSvc mapped reads.

On the observed PEX88096, the safe memory-mapped CS0 prefix is `0x500000`
bytes. At flash offset `0x500000`, the nominal flash mapping reaches BAR0
offset `0x800000` and overlaps Atlas port registers; treating the rest of BAR0
as flash produces changing register data. The normalized JEDEC ID is
`EF 60 18`, a 128-Mbit (16 MiB) Winbond device. `backup-flash` therefore reads
the first 5 MiB through the mapped window and the remaining 11 MiB through
serial SPI, and it refuses any other unproven flash ID. A claimed 64 MiB dump
based on the SDK's hard-coded geometry would be four times too large.

`prepare-station` performs two complete flash reads and requires them to match
before deriving anything. It validates the live SBR, applies one named station
layout, constructs and validates the preserved 256 KiB recovery image, and
then writes a new plan directory. `prepare-config` performs the same process
for all changes in a configuration file. A plan contains both complete
backups, current and candidate SBRs, current and candidate recovery images,
the normalized applied configuration, before/after JSON inspections, a JSON
diff, and a SHA-256 manifest. The manifest records every changed SBR and flash
offset plus the exact device-bound confirmation needed by `program-plan`.
Preparation never writes or resets the switch.

Every new plan also contains a strict `pexctl.atlas-config-plan.v1`
`PLAN.json`. `plan verify` checks all eleven listed artifacts, including the
human-readable manifest, against fixed names, sizes, and hashes;
requires the two complete flash reads to match; verifies that the saved
recovery region and SBR are exact slices of those backups; reconstructs the
candidate by applying `applied-config.json`; and regenerates both inspections
and the diff byte-for-byte. Plan directories and their listed artifacts must
be regular files rather than symlinks.

`device program-plan` performs that complete offline verification before it
opens the live device. It then requires the plan BDF and PCI identity to match
the requested PEX88096 (`1000:c010`), requires any expert acknowledgements
again, and passes the already-verified in-memory recovery images to the same
live-current-match, erase, program, and read-back path. This is the normal
write interface.
`program-sector0` remains available as a lower-level recovery primitive for
independently constructed recovery images.

## Understood SoC fields

The following fields are writable through `pexctl.atlas-config.v1`:

| Field | Encoding | Status |
|---|---|---|
| `soc.upstream_port` | first SoC dword, bits 7:0 | vendor field name and width confirmed |
| `soc.max_link_speed` | first SoC dword, bits 9:8; 0–3 = Gen1–Gen4 | vendor encoding confirmed |
| station layout | four packed 3-bit quarter codes per station | only the two complete layouts below are writable |

The first-dword PCIe lane-enable field at bits 15:13 is reported as
`lane_enable_code_raw`; its value semantics are not yet established. JSON also
names 33 expert fields in SoC dwords
`0x68`–`0x70`, including DPR, link-training, clock, hot-plug, power, watchdog,
secure-boot, and ECC controls. Their positions and vendor names are known, but
write behavior has not been independently validated. These fields are
available only through the expected-current and command-line opt-in mechanism
above. Every SoC dword remains available as raw inspection data and is retained
byte-for-byte.

## PSB and SerDes write records

The variable PSB block contains 8-byte register-write records. Each record
stores the 32-bit value followed by a descriptor. The descriptor contains a
20-bit dword address, a four-bit byte mask, and a broadcast flag; `pexctl`
reports the reconstructed byte address as `register_offset` and retains both
the raw descriptor and any reserved bits. Registers observed in the live image
or the PEX88096 RDK also receive stable keys and descriptive names; unknown
offsets remain unnamed instead of being guessed.

The variable PSB-SerDes block contains 8-byte AXI-write records, with the
32-bit address followed by the 32-bit value. Addresses whose bits 30:28 are
all set encode the vendor broadcast modes `none`, `lane`, `station`, or
`lane+station` in bits 25:24. Other addresses are reported with no applicable
broadcast mode.

Both blocks are validated as complete 8-byte records and against the vendor
maximum sizes. Their values can be patched through the separate
`--allow-expert-entries` path. A PSB patch must supply an existing entry index,
a known non-reserved `register_key`, its exact expected descriptor, and its
exact expected value. It may change only bytes selected by the descriptor's
byte mask. A PSB-SerDes patch must supply an existing index, exact expected
address, and exact expected value. Every expectation is checked before any
change occurs.

The patch path cannot add, remove, reorder, resize, retarget, rebroadcast, or
change the byte mask of a record. It changes only the value dword and updates
the SBR checksum. This exposes the structurally understood configuration
without pretending the register-specific reset and board behavior is safe.
The JSON fields accept either unsigned integers or quoted hexadecimal values;
normalized configurations serialize them as eight-digit hexadecimal strings.
Missing expert acknowledgement is rejected before `prepare-config` opens or
reads the live device.

`export-entry-patch` generates this strict document from an existing image.
It fills in the current key and descriptor/address and expected value, rejects
unknown or read-only PSB records, enforces the byte mask, and refuses a no-op
replacement. Generation does not imply that the requested register value is
safe.

Examples are
[`expert-psb-entry.json`](examples/expert-psb-entry.json) and
[`expert-psb-serdes-entry.json`](examples/expert-psb-serdes-entry.json).
They demonstrate syntax against this board's current image and are not
recommendations to make those value changes.

## PSW lane defaults

The vendor Atlas field database defines one PSW block for each of stations
0 through 5 and one smaller PSWx2 block. An enabled station PSW is exactly
16 bytes, one byte per lane. Bits 2:0 are `ssc_default`, bits 4:3 are
`protocol_default`, bits 6:5 are reserved, and bit 7 is `soft_control`.
PSWx2 is exactly four bytes: the first two bytes use the same lane layout and
bits 31:16 are reserved.

`sbr psw` and `device psw` decode these values without assigning undocumented
meanings to the numeric SSC and protocol codes. Enabled blocks with a wrong
size or nonzero reserved bits are rejected. The command reports ignored blocks
as ignored and does not substitute the editor's displayed defaults.

PSW mutation is intentionally unavailable. Both the live Strix-4 image and
Broadcom's Base RDK96 image mark every PSW block ignored with offset zero and
size one, so there is no observed enabled payload or safe evidence for adding,
resizing, and reindexing these blocks. This is a read-only format guarantee,
not a claim that PSW settings are unnecessary.

## Port defaults

The Atlas field database defines two-bit `Port Type` and `Clocking mode`
defaults for ports 0 through 95, plus special ports 116 and 117. `sbr ports`
and `device ports` report each raw code, its exact SBR offset and bit range,
and a read-only policy. `--port` selects one supported port; ports 96 through
115 are not present in the database table and are rejected.

The enum meanings are not available in the evidence corpus. More importantly,
all 98 type codes and all 98 clock-mode codes are zero in both the live
all-x16 image and Broadcom's fan-out Base RDK96 image. These tables therefore
do not distinguish the proven x16 and x4+x4+x4+x4 station layouts. `pexctl`
does not invent names for zero and does not permit these values to be changed.

## PEX88096 station topology

Six 16-lane stations are described by four 3-bit quarter codes each. The
packed field begins at SBR bit `0x5e * 8`.

Known encodings:

| Codes | Meaning | Evidence |
|---|---|---|
| `[0,0,0,0]` | one x16 port | all six live switch stations |
| `[1,1,1,1]` | four x4 ports | Broadcom RDK96 fan-out stations |
| `7` in a quarter | disabled quarter | Broadcom RDK96 unused quarters |

Only the first two complete layouts are currently writable by name. Unknown
or mixed layouts are displayed as raw codes and retained unchanged.

## Hardware-write safety boundary

`program-plan` and its lower-level `program-sector0` primitive are
intentionally narrower than a generic flash writer. The hardware path:

1. requires exact 256 KiB expected-current and candidate recovery images;
2. validates both embedded SBRs and requires equal SBR lengths;
3. rejects every candidate difference outside the SBR;
4. rejects every difference beyond the one 64 KiB block the writer programs;
5. rereads the live sector and requires an exact expected-current match;
6. requires a confirmation phrase bound to the BDF, CS0, and sector 0;
7. reads all three flash status registers and refuses BUSY, suspended,
   unexpectedly write-enabled, or protected target state;
8. refuses any nonzero BP or CMP setting when WPS selects status-register
   protection, rather than guessing whether the setting covers block 0;
9. reads and requires an unlocked address-zero sector when WPS selects
   individual block locks;
10. verifies that WEL becomes one after every Write Enable and returns to zero
    after every accepted erase or page-program operation;
11. erases only the first 64 KiB block with `D8`, programs only its non-erased
    pages, and waits for every operation to finish;
12. rereads and compares the complete 256 KiB recovery region before returning
    success;
13. never changes protection registers and never resets the PEX switch.

`program-plan` adds the plan-wide artifact, configuration-reconstruction, and
device-binding checks described above before reaching this hardware path.

This removes common software mistakes; it does not make an interrupted block
erase recoverable. Do not run the command without an out-of-band way to
restore CS0 block 0 and a verified cold power-cycle path.

The protection checks follow the W25Q128JW status-register and individual-lock
definitions, while the recovery boundary follows the PLX SDK FAQ warning that
write protection can make SDK writes fail and a corrupt nonvolatile image can
remove the in-band repair path. The board-specific evidence and exact source
sections are recorded in the Strix-4
[`FLASH-PROTECTION.md`](../../hardware/pex880xx-strix-4/FLASH-PROTECTION.md)
dossier.

## License

MIT. See `LICENSE`. PlxSvc ABI and Atlas SPI protocol interoperability work is
documented in `THIRD_PARTY-NOTICES.md`.
