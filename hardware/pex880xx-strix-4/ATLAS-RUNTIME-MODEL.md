# PEX88096 runtime register model (Atlas)

This note consolidates the multi-agent research of 2026-07-29 with the local
evidence into one runtime model. Evidence tiers: **[SDK]** = vendor SDK 8.23
source (local, `Windows_Api/PlxApiDirect.{c,h}`, `Windows_Drivers/Source.PlxSvc`,
`Include_Header_Files`); **[PDE-DB]** = vendor PDE device database extraction;
**[BRIEF]** = Broadcom public product briefs; **[OEM]** = Serial Cables manuals
and field reports; **[HYP]** = hypothesis with stated basis, not yet proven.

## Address spaces and access paths

Atlas has several register/address spaces:

| Space | Base | Access from host |
|---|---|---|
| Port CSR ("PEX region") | chip `0x6080_0000`, mapped at BAR0 `0x80_0000` [SDK: `ATLAS_REGS_AXI_BASE_ADDR`, `ATLAS_PEX_REGS_BASE_OFFSET`] | direct BAR0 dword read/write (pexctl `device reg-read`) |
| CCR (chip config) | chip `0xFFF0_0000` [SDK: `ATLAS_REGS_AXI_CCR_BASE_ADDR`] | IDX_AXI indirect window |
| Maverick (boot/CPU) | chip `0x6000_0000` [SDK: `ATLAS_REGS_AXI_MAVERICK_BASE_ADDR`] | IDX_AXI |
| PBAM | chip `0x2A0C_0000` (PCI `0x001C_0000`) [SDK] | IDX_AXI |
| SPI CS0 flash | AXI `0x1000_0000`, PCI window at BAR0 `0x30_0000` [SDK] | direct mapped window (pexctl flash path) |

**IDX_AXI indirect window** [SDK `I2cAaUsb.c`, `PlxApiDirect.h`]: three dwords in
the PEX region at chip `0x6080_0000 + 0x1F0100` → BAR0 `0x9F0100`:

| BAR0 offset | Register | Use |
|---:|---|---|
| `0x9F0100` | IDX_AXI_ADDR | AXI address to access |
| `0x9F0104` | IDX_AXI_DATA | data read/written |
| `0x9F0108` | IDX_AXI_CTRL | bit0 = write command, bit1 = read command, bit2 = busy, bit3 = read-valid |

Read sequence: write ADDR, write `0x2` to CTRL, poll CTRL busy/read-valid,
read DATA. Write: write ADDR, write DATA, write `0x1` to CTRL, poll busy.
This reaches the full AXI space (CCR, Maverick, PBAM, SPI) from the host.

## Switch operating modes [SDK `PlxApiDirect.c` probe]

`ATLAS_REG_CCR_PCIE_SW_MODE` = CCR `0xB0`, bits [1:0]:

- `0` = **Standard** (base fan-out). Upstream port from `0x360[7:0]`
  (`ATLAS_REG_VS0_UPSTREAM`). This is the live Strix-4 configuration.
- `1` = **Fabric** ("SSW", synthetic). Management port from CCR `0x170[15:8]`
  (`ATLAS_REG_CCR_PCIE_CONFIG`). Embedded Cortex-R4 synthesizes the per-host
  hierarchy; MPT/GEP/internal-management ports are only probed in this mode.
- `2`, `3` = unknown/unsupported.

[BRIEF BC-0484EN] names the modes **Base**, **Base+MPT** (fan-out plus MPT
management endpoint), **Synthetic**. [OEM] maps `fdl sbr` → Base,
`fdl fw` → Synthetic, with the heartbeat LED solid vs blinking on Atlas2.

**[HYP]** SBR SoC dword 3 bits [17:16] ("Atlas mode.") is the persistent
counterpart of CCR `0xB0[1:0]`; live image `0` = Standard. Basis: same width,
mode vocabulary match, SBR is the boot source of CCR straps.

## Port types

**CCR runtime** [SDK]: `ATLAS_REG_CCR_PORT_TYPE0` = CCR `0x120`, one dword per
16 ports, two bits per port — same packing as the SBR Port Type table. The SDK
reads it only in fabric mode: a downstream port whose 2-bit field is `1` is a
**fabric port** (`PLX_SPEC_PORT_FABRIC`). `0` = standard/transparent.
`2`, `3` = unknown (not decoded in public SDK source).

**[HYP]** The SBR Port Type table (SoC dwords 25–32) is the boot-time copy of
CCR `0x120..`: identical 2-bit/16-per-dword packing. All reference images hold
`0` (all transparent), consistent with base mode.

## Clocking

Per-port "Clocking mode" (SBR dwords 33–39) remains **enum-unknown**.
[BRIEF] confirms the family supports common clock, SRIS, and SRNS; [OEM] image
names (`HOST_X4_SRIS_V02.bin`) prove clocking is an SBR-level attribute, so
the table is real; values 1–3 unassigned. Runtime "Clock Enable" registers
(`0x30C/0x310/0x314`, port clock gates) are separate [SDK names confirmed].

## Virtual-switch (VS) block — Atlas vs legacy PLX

The VS block addresses inherited from Gen3 PLX exist but with **Atlas-specific
semantics** [PDE-DB, decisive]:

| byte off | Atlas meaning | Legacy Gen3 meaning [SDK PlxMH_*] |
|---:|---|---|
| `0x358` | VS Enable, VS0–3 bits | same (VS0–7) |
| `0x360`–`0x36C` | VS0–3 Upstream registers | same stride, [4:0] port field |
| `0x380`–`0x38C` | **VS0 Port Vector only, 98-bit bitmap (4 dwords)** | VS0–VS7 vectors, one dword each |
| `0x390`–`0x394` | **Reserved** (no VS1/VS2 vectors exist) | VS2/VS3 vectors |
| `0x398`–`0x3A4` | Per-port **Level0 Reset** bitmap (ports 0–95, 116, 117) | VS3–VS7 vectors |
| `0x3A8` | VS PERSTn status/control + NT1-0 PERSTn | VS Reset (0x3A0 legacy collides here) |
| `0x3AC` | Config Release / Initiate Configuration | — |

Consequences:

- The legacy `PlxMH_MigrateDsPorts` flow (move ports between VS dwords) does
  **not** transfer to Atlas: there is exactly one port-vector bitmap (VS0's).
- Basic VS0-only operation (= fan-out with the whole fabric in VS0) is what
  the live board runs. VS1–3 have upstream registers but no membership
  vectors in standard mode; genuine multi-host partitioning is a **fabric
  mode** concern owned by the embedded CPU [SDK: fabric ports + MPT/GEP only
  exist in fabric mode; BRIEF: synthetic = CPU-synthesized hierarchy].
- `Initiate Configuration` (`0x3AC` bit 0) is plausibly the commit trigger
  for VS/port-vector changes [PDE-DB name only; semantics unproven].
- Per-VS and per-NT PERSTn control (`0x3A8`) is real and Atlas-labeled.

## NT (NT2.0), DMA, TWC, MPT

[BRIEF BC-0484EN]: NT2.0, up to 48 NT-capable ports on the largest device;
up to 48 DMA channels/functions (one per x2 port) for host-to-host,
host-to-I/O, I/O-to-I/O transfers; TWC (Tunneled Window Connection) for
short host-to-host packets; two x1 management ports for the mCPU.

[PDE-DB] VS0 Upstream register (`0x360`): upstream port [7:0], NT port
[12:8] + enable bit 13, NT2 port [20:16] + enable bit 21, DMA mode bit 24,
VC mode bit 25, ALUT NT port enable bit 30, ALUT NT2 port enable bit 31.

Drivers: **no Linux mainline or out-of-tree Atlas NTB driver exists**.
FreeBSD `ntb_hw_plx` covers Gen3 PLX (`10b5:87a*/87b*`) only; porting to
Atlas NT endpoints is a new driver project. Linux `mpt3sas` already names
the Atlas management endpoint: `MPI26_ATLAS_PCIe_SWITCH_DEVID = 0x00B2`.

## Flash content finding (2026-07-29, offline analysis of the Strix-4 dump)

The complete 16 MiB CS0 dump contains data **only** in `0x400..0xF50` — the
SBR image itself. The rest is erased (`0xFF`). This board carries **no
synthetic firmware**: it is a pure base-mode configuration. Fabric/synthetic
mode requires a Broadcom FW image (OEM/NDA-distributed; Serial Cables cards
ship one and flash it with `fdl fw`). Secure-boot OPNs (`SS02-0B00-02`)
verify FW signatures; this board's `FlashSigEn` SBR field is clear.

Meta's public OpenBMC PEX88000 driver records the **FW image regions at
flash `0x80000` and `0x200000`** (header pointer at `+0x38`, active flag) —
the slots this board's flash leaves empty
([facebook/openbmc `pex88000.c/h`](https://github.com/facebook/openbmc)).

## Additional public code and firmware sources (2026-07-29 research)

- **SDK v9.81 full Linux source** mirrors the multi-host API
  ([xiallc/broadcom_pci_pcie_sdk](https://github.com/xiallc/broadcom_pci_pcie_sdk)):
  VS registers, `PlxPci_MH_GetProperties`/`MigratePorts`, and the note that
  the SDK deliberately rejects VS-mode operations on Atlas — the vendor
  expects SBR or synthetic-FW configuration, not legacy VS pokes.
- **Meta OpenBMC/OpenBIC PEX88000/PEX89000/PEX90144 drivers**: public source
  for the management transport (the embedded CPU is codenamed "Chime"),
  I2C slave command formats, and the FW flash regions above.
- **Lenovo ThinkSystem 1611-8P** (PEX88048-based NVMe switch card) has
  **publicly downloadable firmware** ([DS552120](https://support.lenovo.com/us/en/downloads/ds552120-thinksystem-1611-8p-nvme-switch-card-firmware-for-anyos)),
  flashed through the MPT3 / UBM (SFF-TA-1005) path that Linux `mpt3sas`
  already binds on Atlas management ports. Lenovo changelogs name the
  component "**Atlas-1 VSFW**" (virtual-switch firmware) and describe
  "synthetic hierarchy" flash boot — direct public evidence that Atlas Gen4
  multi-host firmware exists as a flashable artifact.
- **ALUT pseudo-ports**: `PLX_FLAG_PORT_ALUT_0..3 = 190..193`
  (local `PlxTypes.h:358`): four ALUT RAM arrays are first-class port
  targets.
- Codename ladder from SDK families: Atlas = PEX88000 (Gen4),
  Atlas2 = PEX89000 (Gen5), Atlas3 = PEX90144 (Gen6); note the PDE SDK also
  uses "Capella" for a Gen3 family, so that name is ambiguous.

## Out-of-band and management interfaces

[SDK] API modes enumerate the supported transports: PCI (BAR0), I2C via
Aardvark (`PLX_API_MODE_I2C_AARDVARK`), MDIO splice, and SDB serial
(`SdbComPort.c`). [OEM] Serial Cables Atlas card provides: USB-CDC MCU CLI
(`dr` dump regs, `dp` dump port regs, `df` dump flash, `mw` write register,
`setmode`, `scan` I2C bus, `fdl sbr|fw|mfg`), **J2 jumper = disable SBR
load** (bad-config recovery), `ATLAS_SCL`/`ATLAS_SDA` I2C sideband on
SFF-8644, CN1 SDB UART and CN2 Atlas UART headers. The Atlas I2C target 7-bit
address is not public; the SBR `legacy_plx_i2c_target_enable` field (set on
the live board) suggests PLX-compatible I2C target behavior.

## Consequences for pexctl

1. Add `device reg-write` (expert-gated) and `device axi-read`/`axi-write`
   via the IDX_AXI window, with the same fail-closed style as the flash path.
2. Add decoded runtime views: `device mode` (CCR 0xB0), `device port-types`
   (CCR 0x120 table), `device vs` (VS enable/upstream/vector/PERSTn).
3. Upstream-port move in standard mode: SBR `STRAP_UPSTRM_PORT` (2-byte
   candidate, already validated) + reboot; runtime mirror is `0x360[7:0]`.
4. Multi-host (domains): fabric mode is embedded-CPU/FW territory. Without a
   Broadcom FW image, base-mode experiments are limited to the VS0 block;
   do not promise VS1–3 partitioning from standard mode.
5. NT: hardware fields exist; driver work is a separate, larger project.

## Sources

- SDK 8.23 local extraction: `Windows_Api/PlxApiDirect.{c,h}`,
  `Windows_Api/I2cAaUsb.c`, `Windows_Drivers/Source.PlxSvc/{ApiFunc,SuppFunc,ChipFunc}.c`,
  `Windows_Drivers/Source.PlxSvc/DrvDefs.h`, `Include_Header_Files/PlxTypes.h`.
- PDE 8.23 `Pde/db/pex_device_atlas.db` + `AtlasSBR.db` (reflection probes).
- Broadcom briefs BC-0484EN (PEX88000), PEX89000-PB102 (Capella).
- Serial Cables PCI-AD-x16HE-BG4 and Atlas2 ITAP manuals; STH thread 47497.
- FreeBSD `ntb_hw_plx(4)` + source; Linux `mpt3sas_base.h`.
- Multi-agent research reports: `research/gemini.md`, `research/grok.md`,
  `research/claude.md`, `research/kimi.md` (see `research/RESEARCH-BRIEF.md`).
- Public code: [xiallc/broadcom_pci_pcie_sdk](https://github.com/xiallc/broadcom_pci_pcie_sdk)
  (SDK 9.81), [facebook/openbmc](https://github.com/facebook/openbmc)
  (`pex88000.c/h`), Lenovo 1611-8P public firmware (DS552120).
