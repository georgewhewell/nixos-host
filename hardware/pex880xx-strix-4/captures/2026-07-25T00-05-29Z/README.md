# PEX88096 station-plan capture: 2026-07-25T00:05:29Z

This session validates the open `pexctl device prepare-station` workflow
against the live PEX88096 in Strix-4. It also adds a serial-SPI-only read of
the 256 KiB recovery region as a third transport cross-check.

No SPI erase, page program, PEX reset, host reboot, or topology change was
performed. Strix-4 remained on boot ID
`758399aa-a216-4733-90ad-eab6141f7c18`.

## Serial recovery-region cross-check

`pex88096-cs0-sector0-pexctl-serial.bin` was acquired through Atlas manual
serial SPI commands rather than the BAR0 flash mapping. It is byte-for-byte
identical to:

- both earlier `pexctl` mapped reads;
- the independent Broadcom PlxCm 8.23 read;
- the first 256 KiB of both complete CS0 backups.

```text
size:     262144 bytes (0x40000)
SHA-256:  52dabae4bbeecbb404371e13634d68a565f687cffa74308a67d641edd30ad6bb
```

## Recovery-first station plan

The tested `prepare-station` command:

1. identified CS0 as JEDEC `EF 60 18`;
2. read the complete 16 MiB flash twice;
3. required both reads to be byte-for-byte identical;
4. parsed and validated the live SBR at flash offset `0x400`;
5. changed station 4 from `[0, 0, 0, 0]` to `[1, 1, 1, 1]`;
6. validated the candidate SBR and preserved 256 KiB recovery image;
7. wrote both backups, both SBRs, both recovery images, and `MANIFEST.txt`
   into a newly created output directory.

Both full reads reproduced the previously captured complete-flash SHA-256:

```text
16796f3fa9f0f88276635c60d1e1e2d581393a3eba5f7a03afed9975aa8ab83b
```

The full 16 MiB files are already preserved in
`../2026-07-24T23-34-55Z/` and are not duplicated here. The live manifest is
preserved as `station-plan-MANIFEST.txt`; it contains their individual
hashes and sizes.

## Exact candidate reproduction

The new command independently reproduced every previously derived artifact:

```text
current SBR:
f4e0bf5d1d01d3f8daccc7c9c792cf0174e509a725379a646c9704c2cd4caae5

candidate SBR:
3736c9fc9d67e99152fa834208ec303ccc2ebe0c60c8518777ab44eb9f87c0ea

current recovery region:
52dabae4bbeecbb404371e13634d68a565f687cffa74308a67d641edd30ad6bb

candidate recovery region:
eae37576515486e0e00db49d96e89ef26c9e02b4d34f9db1800b44fd44af4ce1
```

Exactly three SBR bytes differ:

```text
SBR 0x0064 / flash 0x0464: 00 -> 49
SBR 0x0065 / flash 0x0465: 00 -> 02
SBR 0x0b4c / flash 0x0f4c: 1a -> cf (checksum)
```

Both SBRs passed structural and checksum validation. The plan records
`hardware-written: no`.

## Write boundary

The plan is sufficient input for the recovery-gated writer, but it is not
permission to run it. An interrupted first-block erase can leave the PEX
unable to enumerate, so software and netboot recovery are insufficient.
Programming remains blocked on explicit confirmation that an out-of-band CS0
SPI restore path is connected and usable.
