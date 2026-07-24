# PEX88096 open-tool and recovery capture: 2026-07-24T23:34:55Z

This session validates the open `pexctl` implementation against live hardware,
captures the complete CS0 flash twice, preserves the SBR erase region with two
independent readers, and builds a sector-preserving station-4 candidate.

No SPI erase, page program, PEX reset, host reboot, or topology change was
performed. Strix-4 remained on boot ID
`758399aa-a216-4733-90ad-eab6141f7c18`.

## Device and flash identity

```text
PEX BDF:       0000:c4:00.0
PCI ID:        1000:c010
PEX revision:  B0
SPI CS:        0
JEDEC ID:      EF 60 18
capacity:      128 Mbit / 16 MiB
```

The Broadcom SDK hard-codes Atlas CS0 as 64 MiB, but the live JEDEC capacity
byte and two exact 16 MiB reads show that this board has a 16 MiB device.

## Memory-map boundary correction

Atlas maps CS0 at BAR0 offset `0x300000`, while Atlas port registers begin at
BAR0 offset `0x800000`. Only the first `0x500000` bytes of flash are therefore
safe to read through the mapped window.

An initial experiment treated all remaining BAR0 space as flash. Two such
reads first differed at flash offset `0x5003f6`, which maps to BAR0 offset
`0x8003f6`; additional differences repeated in live port-register ranges.
Those invalid images were discarded and are not recovery artifacts.

The corrected `pexctl backup-flash` path reads:

```text
flash 0x000000..0x4fffff: PlxSvc mapped-register reads
flash 0x500000..0xffffff: serial SPI read commands
```

## Complete CS0 backups

`pex88096-cs0-complete-pexctl-a.bin` and
`pex88096-cs0-complete-pexctl-b.bin` are byte-for-byte identical:

```text
size:     16777216 bytes (0x1000000)
SHA-256:  16796f3fa9f0f88276635c60d1e1e2d581393a3eba5f7a03afed9975aa8ab83b
```

Both were captured independently with the corrected mixed mapped/serial path.

## Recovery-region backups

The 256 KiB region at CS0 offset 0 contains the SBR and the complete first
64 KiB block affected by the SDK's `D8` erase command. All three region
captures are byte-for-byte identical:

```text
pex88096-cs0-sector0-pexctl-a.bin
pex88096-cs0-sector0-pexctl-b.bin
pex88096-cs0-sector0-plxcm.bin

size:     262144 bytes (0x40000)
SHA-256:  52dabae4bbeecbb404371e13634d68a565f687cffa74308a67d641edd30ad6bb
```

The first two use `pexctl`; the third is an independent Broadcom PlxCm 8.23
`spisave /mmr /nr` read. The complete CS0 backups have the same 256 KiB
prefix.

## SBR transport validation

`pex88096-current-sbr-pexctl.bin` was read through the new pure-Rust PlxSvc
ioctl transport:

```text
flash offset: 0x400
size:         2896 bytes (0xb50)
SHA-256:      f4e0bf5d1d01d3f8daccc7c9c792cf0174e509a725379a646c9704c2cd4caae5
```

It is byte-for-byte identical to the earlier complete PlxCm SBR capture and
passes structural and checksum validation.

## Station-4 candidate

`pex88096-cs0-sector0-station4-x4x4x4x4-candidate.bin` is the preserved 256
KiB recovery region with the validated candidate SBR inserted at `0x400`.
Relative to the live recovery image, exactly three bytes differ:

```text
flash offset 0x0464: 00 -> 49
flash offset 0x0465: 00 -> 02
flash offset 0x0f4c: 1a -> cf (SBR checksum)
```

```text
candidate-region SHA-256:
eae37576515486e0e00db49d96e89ef26c9e02b4d34f9db1800b44fd44af4ce1

extracted candidate SBR SHA-256:
3736c9fc9d67e99152fa834208ec303ccc2ebe0c60c8518777ab44eb9f87c0ea
```

The extracted SBR validates and matches the standalone candidate. The
candidate has **not** been programmed.

## Write boundary

`pexctl device program-sector0` exists but was not run. It requires:

- an exact 256 KiB expected-current match against live flash;
- equal-length valid current and candidate SBRs;
- no changed byte outside the SBR;
- the exact confirmation string bound to BDF, CS0, and sector 0;
- erase/program completion polling;
- a complete 256 KiB read-back match;
- no automatic PEX reset.

Software checks do not replace out-of-band SPI recovery. Do not program until
that recovery path and the cold power-cycle path are verified.
