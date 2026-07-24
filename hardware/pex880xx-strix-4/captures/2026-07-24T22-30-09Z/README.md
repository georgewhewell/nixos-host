# PEX88096 SBR and port-topology capture: 2026-07-24T22:30:09Z

This capture maps the live PEX88096 ports and saves the active Serial Boot
ROM image used to configure the switch. The SBR was read from SPI chip select
0 at flash offset `0x400`; no register, SPI, reset, or configuration write
was performed.

## Result

The ASUS Hyper M.2 carrier is attached to the PEX station represented by
lanes/ports `0x40` through `0x4f` (decimal 64 through 79). The live SBR exposes
that station as one x16-capable downstream port:

```text
PEX port 0x40 (64): x16 capable, Gen4 x4 active, NVMe at 0000:cf:00.0
PEX port 0x44 (68): not exposed as a logical downstream port
PEX port 0x48 (72): not exposed as a logical downstream port
PEX port 0x4c (76): not exposed as a logical downstream port
```

The one visible Corsair drive is therefore using the first four lanes of a
single x16 logical port. Linux cannot enumerate the other three carrier
positions because the switch does not currently expose three additional
downstream ports.

The required target topology for this station is:

```text
PEX port 0x40 (64): x4, carrier position 1
PEX port 0x44 (68): x4, carrier position 2
PEX port 0x48 (72): x4, carrier position 3
PEX port 0x4c (76): x4, carrier position 4
```

This is a PEX88096 SBR topology change. It is not AMD/Strix slot bifurcation,
and `pci=realloc=on` cannot create the missing logical ports. PCI resource
reallocation remains useful after the topology change because Linux will need
bridge windows and BAR space for three additional endpoints.

## Other live ports

PlxCm uses hexadecimal port numbers:

```text
0x00: PEX upstream toward Strix-4, Gen4 x4 active / x16 capable
0x10: BlueField-2 branch, Gen4 x16 active
0x20: x16 downstream port, no link
0x30: x16 downstream port, no link
0x40: ASUS/NVMe branch, Gen4 x4 active / x16 capable
0x50: x16 downstream port, no link
0x74: x1 downstream port, no link
0x75: x1 downstream port, no link
```

Port `0x50` belongs to the next 16-lane station. It is not the second quarter
of the ASUS carrier's station.

## SBR backups and correction

The first read, `pex88096-current-sbr.bin`, is only a prefix:

```text
flash CS:     0
flash offset: 0x400
size:         0xa68 bytes (2664)
SHA-256:      c2fae9ab6f37a431badbafbbf362f14a166edcf5997d49c01b4b1f8291fa888d
```

That size came from Broadcom's `Base_RDK96_v0.0.1.0.bin`, not from the live
image. The live index describes a `0xb50`-byte image, so the old file ends
inside the live `PSB_SERDES` block and is not a complete or restorable SBR.
It remains here as immutable acquisition evidence.

The complete active SBR is `pex88096-current-sbr-full.bin`:

```text
flash CS:     0
flash offset: 0x400
size:         0xb50 bytes (2896)
SHA-256:      f4e0bf5d1d01d3f8daccc7c9c792cf0174e509a725379a646c9704c2cd4caae5
checksum:     0x1a at SBR offset 0xb4c, valid
```

The complete read also used `/mmr /nr`. Strix-4 remained on boot ID
`758399aa-a216-4733-90ad-eab6141f7c18`.

Broadcom's RDK96 image is `0xa68` bytes and differs in both structure and
configuration. Do not replace the live board image with the reference image.

## Candidate topology image

The open `pexctl` implementation decoded the Atlas station field from the
live image, Broadcom's RDK96 image, and the SDK's Atlas database. Station 4 is
the ASUS carrier branch.

`pex88096-station4-x4x4x4x4-candidate.bin` changes station 4 from codes
`[0,0,0,0]` to `[1,1,1,1]` and recalculates the SBR checksum:

```text
SBR offset 0x0064: 00 -> 49
SBR offset 0x0065: 00 -> 02
SBR offset 0x0b4c: 1a -> cf (checksum)
SHA-256: 3736c9fc9d67e99152fa834208ec303ccc2ebe0c60c8518777ab44eb9f87c0ea
```

No other byte changes. The candidate validates as a `0xb50`-byte PEX88096
SBR. It has **not** been programmed.

## Programming requirements

The SBR begins at `0x400` inside CS0 block 0. A safe programming operation must
preserve the complete erase unit and verify it after programming; a short raw
write is not sufficient.

Before programming anything:

1. Capture two matching complete CS0 images using detected JEDEC geometry.
2. Capture the complete recovery region containing block 0 with an independent
   reader.
3. Establish an out-of-band recovery path and a verified cold power-cycle.
4. Require the live recovery bytes to match the expected backup immediately
   before erase.
5. Erase and restore the complete affected block, then compare a full
   read-back before any reset.

Applying a new boot topology requires a PEX reset or cold power cycle. Treat
that as disruptive to every endpoint behind the switch, including the
BlueField-2 and all NVMe devices.

## Runtime tool note

`PlxSvc` loaded successfully, but the netboot tmpfs did not contain its legacy
device node. PlxCm enumerated the switch after creating
`/dev/plx/PlxSvc` with the dynamically allocated character major and minor
255. A NixOS helper or service should create that node before future PlxCm
use.
