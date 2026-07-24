# pexctl

`pexctl` is an open, command-line replacement for the configuration parts of
Broadcom's PLX SDK and PEX Device Editor. The initial target is the Atlas
PEX88000 family, tested against a PEX88096.

The design is deliberately recovery-first:

- parse every image losslessly and preserve unknown bytes;
- derive image length from the SBR index instead of a reference filename;
- validate all block ranges and the hardware checksum before mutation;
- expose only field encodings supported by observed hardware and reference
  images;
- write candidates to new files and refuse accidental overwrites;
- never write hardware until complete-sector preservation and read-back
  verification are available.

## Current commands

```console
pexctl sbr inspect IMAGE
pexctl sbr validate IMAGE
pexctl sbr diff BEFORE AFTER
pexctl sbr set-station INPUT --station 4 --layout x4x4x4x4 --output candidate.bin
pexctl sbr repair-checksum INPUT --output repaired.bin

pexctl flash extract-sbr flash.bin --output current.bin
pexctl flash replace-sbr flash.bin candidate.bin --output candidate-flash.bin

sudo pexctl device read-sbr --bdf 0000:c4:00.0 --output current.bin
sudo pexctl device read-flash --bdf 0000:c4:00.0 \
  --offset 0 --size 0x40000 --output sector-0.bin
sudo pexctl device spi-id --bdf 0000:c4:00.0
sudo pexctl device backup-flash --bdf 0000:c4:00.0 \
  --output complete-cs0.bin

sudo pexctl device program-sector0 --bdf 0000:c4:00.0 \
  --expected-current sector-0.bin --candidate candidate-sector-0.bin \
  --confirm ERASE-PROGRAM-VERIFY:0000:c4:00.0:CS0:SECTOR0
```

The device reader accesses the Atlas CS0 memory-mapped flash window through the
open PlxSvc ioctl ABI from Broadcom's dual-BSD/GPL SDK. It verifies the PCI
address and device identity against sysfs and PlxSvc independently, checks the
driver ABI version, derives the SBR length from its index, and validates the
resulting checksum. It issues mapped-register reads only; it does not reset the
switch or write a register.

On the observed PEX88096, the safe memory-mapped CS0 prefix is `0x500000`
bytes. At flash offset `0x500000`, the nominal flash mapping reaches BAR0
offset `0x800000` and overlaps Atlas port registers; treating the rest of BAR0
as flash produces changing register data. The normalized JEDEC ID is
`EF 60 18`, a 128-Mbit (16 MiB) Winbond device. `backup-flash` therefore reads
the first 5 MiB through the mapped window and the remaining 11 MiB through
serial SPI, and it refuses any other unproven flash ID. A claimed 64 MiB dump
based on the SDK's hard-coded geometry would be four times too large.

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

`program-sector0` is intentionally narrower than a generic flash writer. It:

1. requires exact 256 KiB expected-current and candidate recovery images;
2. validates both embedded SBRs and requires equal SBR lengths;
3. rejects every candidate difference outside the SBR;
4. rereads the live sector and requires an exact expected-current match;
5. requires a confirmation phrase bound to the BDF, CS0, and sector 0;
6. erases only the first 64 KiB block with `D8`, programs only its non-erased
   pages, and waits for every operation to finish;
7. rereads and compares the complete 256 KiB recovery region before returning
   success;
8. never resets the PEX switch.

This removes common software mistakes; it does not make an interrupted block
erase recoverable. Do not run the command without an out-of-band way to
restore CS0 block 0 and a verified cold power-cycle path.

## License

MIT. See `LICENSE`. PlxSvc ABI and Atlas SPI protocol interoperability work is
documented in `THIRD_PARTY-NOTICES.md`.
