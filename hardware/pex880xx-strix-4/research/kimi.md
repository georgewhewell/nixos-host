# PEX88096 ("Atlas") research report — agent: kimi

Research executed 2026-07-29/30 per RESEARCH-BRIEF.md. Citations inline. Items
marked **UNKNOWN** could not be confirmed; items marked *INFERRED* are reasoned
from cited evidence but not directly stated by a source.

## Q1 — SBR "Port Type" and "Clocking mode" 2-bit field enums

**Clocking mode — largely answered (names), numeric mapping UNKNOWN.**
The four per-port clocking architectures are named exactly by KCORES_OldMonster
(OSHWHub PEX88048/88096 designer) in his PEX88048 design notes (Bilibili mirror
cv39904570, §clocking): **CC** (通用时钟 common clock), **CCS** (带展频通用时钟
common clock with spread spectrum), **SRNS** (独立基准无展频 separate reference,
no SSC), **SRIS** (separate reference, independent SSC) —
[bilibili cv39904570](https://www.bilibili.com/read/cv39904570/).
Four modes ↔ 2 bits is strongly suggestive, but no source gives the numeric
0–3 encoding. UNKNOWN which value is which; the full SDK 9.81 source, its
PDFs, OpenBMC/OpenBIC and global Sourcegraph search contain **no** SRIS/SRNS/
clocking-mode enums either (negative result, SDK-mining subagent). Note all
reference images hold 0 and the KCORES V1.1 card defaults to **CC mode**,
consistent with 0 = CC (common clock) *INFERRED*.

Corroborating evidence that these modes are per-port SBR-selectable:

- Serial Cables **Atlas3** manual `setmode` table: six pre-baked "SBR modes"
  (0–5) each listing per-connector width **and clocking**, e.g. mode 0 =
  `Golden finger X16(SSC) | Straddle X16(SRNS) | Left MCIO X16(SRNS) | Right
  MCIO X16(SRNS)`; modes 1–5 vary only downstream widths (X8/X4/X2) — all
  downstream ports SRNS, host port SSC
  ([Atlas3/Atlas2 combined manual PDF, p.13-14](https://serialcables.com/vendor-media/extra/upload/media/studio_680f727008ea27417341745846400.pdf?title=User-s%20Manual&proId=219)).
  (Caveat: the Atlas3 card is Gen5 — likely PEX89000-based, see Q10 — so this
  table may document Capella's SBR modes; the mechanism is clearly the same
  on both families.)
- Serial Cables 4×4 base-mode SBR file is literally named
  **`B0 HOST_X4_SRIS_V02.bin`** — i.e. host port clocked SRIS
  ([STH thread 47497, post #3](https://forums.servethehome.com/index.php?threads/help-with-serialcables-com-pci4-ad-x16he-bg4.47497/)).
- Atlas2 manual: `spread` command sets SSC down-spread 3000/5000 PPM,
  "usually used for **SRIS** testing", ref clock runs "**CFC** (spread off) or
  SSC"; `clk` disables per-port clock outputs, "usually used for **SRNS or
  SRIS** testing" ([Atlas2 ITAP manual, p.23-24](https://serialcables.com/vendor-media/extra/upload/media/studio_672b8f6ce98be8794561730911612.pdf?title=User%27s%20Manual&proId=74)).
- Hardware strap fallback: **MODE_SEL3** pin selects default clock mode when
  SBR fails to load: low = **SRIS**, high = **SSC-isolation mode** — only 2 of
  4 modes strap-selectable (bilibili cv39904570).
- Board-level: `SYS_REFCLK` mandatory base clock; feed it from an independent
  clock generator for SRNS/SRIS; per-host optional `Sx_PCE_REFCLK` +
  `Sx_PCE_PERST#` pairs; Gen4 refclk jitter budget 0.5 ps RMS (same source).

**Port Type — UNKNOWN, but the register name is real.** No source found
anywhere (English or Chinese) documents the 2-bit per-port "Port Type" field
values. Exhaustive negative result: the full Broadcom **SDK 9.81 source**
(xiallc GitHub mirror), SDK PDFs, release notes, Meta's OpenBMC/OpenBIC PEX
code, and global Sourcegraph search contain **no** SBR "Port Type" or
clocking-mode enums; those names live only in the Windows PDE `.db`
databooks, which have no public mirror (SDK-mining subagent, this session).
One hard lead though: the SDK header defines
**`ATLAS_REG_CCR_PORT_TYPE0 = CCR + 0x120`** (`PlxApi/PlxApiDirect.h:102`,
CCR AXI base `0xFFF00000`) — so "Port Type" is a real CCR register block the
SBR fields presumably load; the SDK gives no field decode. Candidates
consistent with observed silicon personalities (*INFERRED*, not sourced):
transparent vs NT(-link/-virtual) vs management-port roles — pci.ids shows
the chip can expose "Virtual Upstream/Downstream Port" (subsys 1000:100b),
"Virtual PCIe TWC/NT2 Endpoint" (1000:2004) and "Virtual PCIe gDMA Endpoint"
(1000:2005) functions ([pci-ids.ucw.cz](https://pci-ids.ucw.cz/v2.2/pci.ids),
vendor 1000 device c010/c012); the SDK adds synthetic personality constants
`PLX_SPEC_PORT_SYNTH_TWC=14, SYNTH_EN_EP=15, SYNTH_NT=16, SYNTH_MPT=17,
SYNTH_GDMA=18, SYNTH_NIC=13` (`Include/PlxTypes.h:595-600`). All reference
images holding 0 suggests 0 = default transparent. The vendor PDE contains no
enum labels (brief).

**Related discrepancy worth flagging** (station quarter width codes, dword 0):
the brief's RDK-derived decoding is 0=x16, 1=x4, 7=disabled. The Chiphell
hands-on SBR-editing thread documents (via PDE `STRAP_STN0..5_PORTCFG` Q0–Q3):
**x16=0, x4=1, x1=4, x8=7** ([chiphell thread
2685098](https://www.chiphell.com/thread-2685098-1-1.html)). These conflict on
the meaning of 7 (and add x1=4/x8=7). Both are cited; treat the code table as
NOT fully settled.

## Q2 — Virtual-switch (multi-host) programming model

**Mostly answered — the VS register block is documented in the public SDK
9.81 source** ([xiallc/broadcom_pci_pcie_sdk](https://github.com/xiallc/broadcom_pci_pcie_sdk),
full Linux source of the Broadcom PCI/PCIe SDK; `Include/Plx.h:67`
`PLX_SDK_VERSION_STRING "9.81"`):

- Public multi-host API: **`PlxPci_MH_GetProperties` /
  `PlxPci_MH_MigratePorts`** (`Include/PexApi.h:690,696`; ioctls
  `PLX_IOCTL_MH_GET_PROPERTIES`, `PLX_IOCTL_MH_MIGRATE_DS_PORTS` in
  `Include/PlxIoctl.h:276-277`), implemented in `PlxApi/I2cAaUsb.c`
  (`PlxI2c_MH_GetProperties` line 1794, `PlxI2c_MH_MigrateDsPorts` lines
  1944–2065) and `Driver/Source.PlxSvc/ApiFunc.c:3267`. Data structure
  `PLX_MULTI_HOST_PROP` (`Include/PlxTypes.h:829-840`): `VS_EnabledMask`
  (U16), `VS_UpstreamPortNum[8]`, `VS_DownstreamPorts[8]` — **up to 8 VS**.
- **`0x354` Management Port Config**: `[4:0]` active mgmt port, `[5]` active
  enable, `[12:8]` redundant mgmt port, `[13]` redundant enable
  (`I2cAaUsb.c:1827,1845-1856`).
- **`0x358` VS Enable**: one bit per VS; "`358[7:0]: 01h=Std else VS mode`"
  (`I2cAaUsb.c:1830,3463-3466`).
- **`0x360 + i*4` = VS_i Upstream** — **this formula confirms VS1/2/3
  Upstream = 0x364/0x368/0x36C** exactly as the team's DB suspected;
  upstream port number in `[4:0]` (`I2cAaUsb.c:1873-1881`); on Atlas the
  read takes 8 bits (`PlxApi/PlxApiDirect.c:2885`). On the Gen3 families the
  same register also packs NT fields (`[13]` NT0 en, `[11:8]` NT0 port,
  `[21]` NT1 en, `[19:16]` NT1 port, `I2cAaUsb.c:3500-3511`) — matching the
  team's VS0-Upstream layout; *INFERRED*: VS1-3 Upstream on Atlas use the
  same low-bits-only encoding (port number, no NT fields).
- **`0x380 + i*4` = VS_i downstream port vector**, one bit per port
  (`I2cAaUsb.c:1883-1891`) — so per-VS port vectors DO exist at the same
  base for all VS; the SDK's U32/`[23:0]` form covers ≤24-port Gen3 chips,
  while Atlas widens the vector to the 98-bit map the team found at
  `0x380–0x38C` (VS0). Exact Atlas VS1–3 vector placement (immediately after
  VS0's 4 dwords, i.e. `0x390+`?) is *INFERRED*, not confirmed.
- **`0x3A0` per-VS reset**: one bit per VS; pulse high ~10 ms then low after
  port migration (`I2cAaUsb.c:2039-2061`).
- **Port membership migration procedure** (`PlxI2c_MH_MigrateDsPorts`): read
  MH props → verify device is in VS mode *and* accessed via the management
  port → clear port bits in source VS vector (`0x380..`), set bits in dest
  VS vector → set dest bit in VS Enable `0x358` → pulse the source VS's bit
  in per-VS reset `0x3A0`. This is the closest thing to a documented
  bring-up/membership sequence.
- Detection heuristic (`I2cAaUsb.c:1827-1839`): if `0x354` reads 0 and
  `0x358 == 0x01`, the device is in VS mode but you're **not** on the
  management port (MH properties are only readable from the mgmt port).
- **Critical caveat**: the SDK's `PlxMH_*`/`PlxI2c_MH_*` functions
  **reject PLX_FAMILY_ATLAS** ("doesn't support VS mode",
  `I2cAaUsb.c:1812-1824`); on Atlas the SDK only reads `0x360` during chip
  probe. PlxCm still exposes `mh_prop` (`Samples/PlxCm/Monitor.c:94`). So on
  Atlas, Broadcom expects VS configuration to come from SBR/synthetic FW,
  not host API calls — the registers exist and decode as above, but the
  vendor host tooling deliberately refuses to drive them.

Bus-level evidence:

- **Synthetic-mode VS resources appear on the PCI bus as distinct virtual
  devices.** pci.ids (vendor 1000, devices c010 and secure variant c012):
  subsys `1000:100b` = "PEX88000 PCIe Gen 4 Virtual Upstream/Downstream Port",
  `1000:2004` = "PEX88000 Virtual PCIe TWC/NT2 Endpoint", `1000:2005` =
  "PEX88000 Virtual PCIe gDMA Endpoint", with the explicit pci.ids comment
  *"Virtual endpoint used in Broadcom synthetic PCIe switches for resource
  reservation"*; c012 is annotated "secure part version of this chip"
  ([pci-ids.ucw.cz](https://pci-ids.ucw.cz/v2.2/pci.ids)). The SDK names the
  same personalities: `PLX_SPEC_PORT_SYNTH_TWC/EN_EP/NT/MPT/GDMA/NIC`
  (`Include/PlxTypes.h:595-600`, class text in `Samples/PlxCm/PciDev.c`).
- TWC = "Tunneled Window Connection (Multi-Host Communication)" — acronym
  expansion in Broadcom's selection guide ([BC00-0445EN
  PDF](https://docs.broadcom.com/doc/BC00-0445EN)). On the Gen3 PEX9700
  family the same table lists "TWC Ports" counts (e.g. PEX9797: 24) —
  TWC/NT is the long-standing multi-host mechanism Atlas inherits.
- The aichiplink PEX88048 overview describes the ExpressFabric model:
  multiple hosts each seeing only assigned devices, a management CPU with
  full switch visibility, dynamic reassignment
  ([aichiplink SS05-0B00-00](https://aichiplink.com/blog/SS05-0B00-00-Review-The-PEX88048-Backbone-of-PCIe-4.0-ExpressFabric_1010)) — marketing-tier.
- Contrast datapoint (what "good" looks like): Microchip Switchtec
  multi-host partitions are publicly documented and the community **c-payne
  tool** reassigns arbitrary ports as upstream/downstream on the Gen5 PM50100
  ([c-payne.com/c-payne-tool](https://c-payne.com/c-payne-tool), described in
  [L1T post 4040237](https://forum.level1techs.com/t/171428/918)) — Broadcom
  restricts equivalent capability to OEM tooling (Q7).

## Q3 — "Atlas mode" (2-bit) and STRAP_FANOUT_EN semantics

**"Atlas mode" decoded (runtime register)**: the SDK header names it
**`ATLAS_REG_CCR_PCIE_SW_MODE` = CCR `0xB0[1:0]`** (`PlxApi/PlxApiDirect.h:101`,
CCR AXI base `0xFFF00000`), decoded in `PlxApi/PlxApiDirect.c:2865-2933`:
**0 = Standard/base** (upstream port taken from `0x360[7:0]`); **1 =
Fabric/SSW** (on Atlas-1 the management port comes from CCR `0x170[15:8]`;
on Atlas2 from CCR `0x1A4[7:0]` = `ATLAS2_REG_CCR_UPSTREAM_PORT`); **2 =
Standard, Atlas2-only**; **3 = invalid**. Related CCR registers:
`ATLAS_REG_CCR_DEV_ID` (CCR+0x0), `ATLAS_REG_CCR_PORT_TYPE0` (CCR+0x120),
`ATLAS_REG_CCR_PCIE_CONFIG` (CCR+0x170) (`PlxApiDirect.h:100-103`). The SBR
"Atlas mode" bits almost certainly load this CCR field — so the SBR values
map as 0=base(standard), 1=fabric/synthetic *INFERRED*.

**STRAP_FANOUT_EN: not found** in SDK 9.81 source, OpenBMC/OpenBIC, or
global Sourcegraph (negative result). The only strap hit: Gen3 Capella-2
`0x46C` "Strap Configuration" `[15:13]=100b` ⇒ fabric mode
(`I2cAaUsb.c:3470-3483`) — same concept on the older family.

Two boot modes are vendor-confirmed by name in the field:

- **"base fanout switch mode"** vs **"Synthetic switch mode"** — Serial
  Cables Atlas2/Atlas3 manuals: LED6 "Blinking: Indicates the Atlas2 switch
  working in Synthetic switch mode; Solid ON: ... base fanout switch mode";
  `fdl sbr` = "update the SBR file into flash of Atlas2 switch (Applicable in
  **base switch mode**)"; `fdl fw` = "program or upgrade FW into flash of
  Atlas2 switch (Applicable in **Synthetic mode**)"; `fdl mcu` = on-board MCU
  upgrade ([Atlas2 manual p.11-12](https://serialcables.com/vendor-media/extra/upload/media/studio_672b8f6ce98be8794561730911612.pdf?title=User%27s%20Manual&proId=74),
  [Atlas3 manual](https://serialcables.com/vendor-media/extra/upload/media/studio_680f727008ea27417341745846400.pdf?title=User-s%20Manual&proId=219)).
  "Synthetic" is Broadcom's own term — also in the pci.ids comment (Q2) and in
  a Lenovo firmware changelog line "**PEX 89000: synthetic mode BST for B0
  board**" ([lenovo.com YUM change
  history](https://linux.lenovo.com/yum/2024_05/ST558_7Y15_7Y16/RHEL9.3/documents/7Y37A01086_change_history.html)).
- So: **base/fan-out** = SBR-driven plain switch (host software optional);
  **synthetic** = embedded-CPU FW in flash builds the fabric (multi-host/NT/
  virtual endpoints). The runtime register decode is above (0=Standard,
  1=Fabric/SSW, 2=Standard-Atlas2); whether the SBR's "Atlas mode" bits and
  STRAP_FANOUT_EN map 1:1 onto those CCR values is *INFERRED*, not proven.
- **Primary-source confirmation of the synthetic-hierarchy boot flow**: the
  public Lenovo MegaRAID (RAID 930-x) firmware changelog — Broadcom's own MR
  firmware managing downstream Atlas switches — contains the enhancement
  *"Atlas2 BST ER: **Multi host flash boot: create synthetic hierarchy** and
  basic EP and config traffic"* (DCSG01021605) and the defect *"**Atlas-1
  VSFW** BST SBR test fails"* (DCSG01014577) — i.e. Atlas (Gen4) has a "VSFW"
  (virtual-switch firmware) tested against the SBR, and Atlas2 (Gen5) boots
  multi-host **from flash** by creating a synthetic hierarchy
  ([Lenovo RAID 930-x change history](https://linux.lenovo.com/yum/2024_05/ST558_7Y15_7Y16/RHEL9.3/documents/7Y37A01086_change_history.html)).
  Same changelog: "FW assert ... 8 NVMe drives connected behind Atlas"
  (DCSG00936303), "PL fault 0xEA20 when atlas return the unexpected error
  code" (DCSG01081692), "Firmware assertion while performing firmware
  download using offline method on PCIe switch configuration"
  (DCSG00956089), "97xx: SCONS changes ... loading 97xx SBR"
  (DCSG01171935), "DMA error observed during **xtools** 'show' command in
  Atlas behind Aero config" (DCSG01051896) — the same "xtools" family as the
  xutil/xflash seen on Serial Cables cards.
- Hardware strap: Atlas3 card has jumper **J9 "sbr mode sel"** (GND) — a
  board-level strap forcing SBR(base) mode, useful for recovery ([Atlas3
  manual p.3](https://serialcables.com/vendor-media/extra/upload/media/studio_680f727008ea27417341745846400.pdf?title=User-s%20Manual&proId=219)).
- No-SBR behavior: PEX88 removed pin-straps entirely — "必须采用SBR配置…没有
  SBR不能正常运行" (SBR mandatory; KCORES,
  [oshwhub PEX88048 EVM](https://oshwhub.com/malong/pex88048gen4evm)).
  Fallback without valid SBR on PEX88048 = **fixed 12×x4 ports**; MODE_SEL4–8
  choose fallback upstream (bits 8:6 station, 5:4 port); MODE_SEL1 disables
  SBR load; MODE_SEL0 picks flash CS (bilibili cv39904570).
- Broadcom P411W-32P firmware image structure (from its flash tool):
  "Concatenated: YES, **SBR Bootloader: YES**, Config Pages: YES, **Signed
  Block: YES**, KeyUpdate Block: Not Available" ([L1T post
  3921885](https://forum.level1techs.com/t/171428/712)) — synthetic FW images
  are signed and embed an SBR bootloader. Secure-boot signing app notes exist
  (gated): `pex880xx-sb-sign-an102`, `pex89xxx-sb-sign-an100/an102` (Q7).
  OpenBIC's CCR **System Error register** (`0xFFF000A8`) bit list corroborates
  the secure/synthetic boot chain: `ARM_FLASH_SIGNATURE_FAIL`,
  `SECURE_BOOT_FAIL`, **`SBR_LOAD_FAIL`**, `POR_BISR_TIMEOUT`, per-station
  fatal-error bits, `PSB_STATION_FATAL_ERROR` (Meta
  [OpenBIC pex89000.h](https://github.com/facebook/OpenBIC)).

## Q4 — Multi-host bring-up sequence; clocking/board implications

**Register order: partially documented.** `0x3ac` / "Config Release" /
"Initiate Configuration": **NOT FOUND** in any public source (SDK, OpenBMC,
forums). The nearest documented knobs, from the SDK's own multi-host
migration code (`PlxI2c_MH_MigrateDsPorts`, `I2cAaUsb.c:1944-2065`):

1. read multi-host properties (VS mask/upstreams/vectors) — only possible
   from the **management port**;
2. verify VS mode (`0x358 != 0x01`);
3. rewrite per-VS downstream port vectors (`0x380+i*4`);
4. set the destination VS's enable bit in `0x358`;
5. pulse the affected VS's bit in **per-VS reset `0x3A0`** (high ~10 ms,
   then low; `I2cAaUsb.c:2039-2061`).

`0x3ac` bit 0 plausibly commits a staged config in the same spirit (team
note); unconfirmed. On Atlas the vendor flow puts this logic in the
synthetic FW / management-CPU path, not host software (Q2 caveat).

- Clocking per port: CC/CCS/SRNS/SRIS (Q1); Serial Cables ships
  SSC-on-host / SRNS-on-downstream as default; SRIS host images exist.
  Board-level for multi-host: **each host gets one PERST + one refclk pair**
  (`Sx_PCE_PERST#`/`Sx_PCE_REFCLK`, 1.8 V logic); `SYS_REFCLK` from an
  independent generator for SRNS/SRIS (KCORES notes, bilibili cv39904570).
  Family has **4 SSC clock domains** ([BC-0484EN
  brief](https://docs.broadcom.com/doc/BC-0484EN) /
  [BC00-0445EN](https://docs.broadcom.com/doc/BC00-0445EN)).
- All Atlas config IO is **1.8 V** (PERST inputs, I2C, UART, straps) — level
  shifting required for 3.3 V host logic (KCORES).
- Field evidence of host↔switch↔host linking: SerialCables BG4 card linked
  card-to-card at Gen4 with a jumper set to "**PCI-SIG**" position (STH
  47497, post #6) — i.e. crosslink/upstream-downstream role juggling works on
  cables, consistent with the per-station crosslink-enable bits (brief).
- Management endpoint in-band bring-up: the mpt3sas-bound management endpoint
  (Q9) exposes MPI26 PCIe-switch config pages (`Mpi26PCIeSwitchPage0/1`,
  per-port `NegotiatedPortWidth/LinkRate`, retimer-presence flags) and PCIe
  topology switch events (`MPI26_EVENT_PCIE_TOPO_SS_*`, including "cascaded
  PCIe Switch removal not supported" TODO) — mainline kernel source
  ([mpt3sas_scsih.c](https://raw.githubusercontent.com/torvalds/linux/master/drivers/scsi/mpt3sas/mpt3sas_scsih.c),
  [mpi2_cnfg.h](https://raw.githubusercontent.com/torvalds/linux/master/drivers/scsi/mpt3sas/mpi/mpi2_cnfg.h)).

## Q5 — NT port configuration; drivers

**Partially answered — NT API + LUT mechanics are public in the SDK; nothing
Atlas-specific.**

- Atlas NT scale: **48 NT ports on PEX88096** (40/32/24/16/12 on
  88080/64/48/32/24) — selection guide
  [BC00-0445EN](https://docs.broadcom.com/doc/BC00-0445EN); Chinese reposts of
  the brief say "48 个非透明桥接（NTB）端口"
  ([eechina 879563](https://www.eechina.com/thread-879563-1-1.html)).
- NT personality devices exist: "Virtual PCIe **TWC/NT2** Endpoint"
  (1000:2004) — NT2 = second NT port, TWC = Tunneled Window Connection for
  multi-host communication (pci.ids, BC00-0445EN). VS0 Upstream register
  carries NT/NT2 port + ALUT-enable fields (brief/team note).
- **NT API (public SDK)**: `PlxPci_Nt_ReqIdProbe`, `PlxPci_Nt_LutProperties`,
  `PlxPci_Nt_LutAdd`, `PlxPci_Nt_LutDisable` (`Include/PexApi.h:709-737`;
  wrappers `PlxApi/PlxApi.c:5915-6124`; ioctls `PLX_IOCTL_NT_LUT_ADD` etc).
  Driver implementation `PlxNtLutAdd` (`Driver/Source.Plx8000_NT/ApiFunc.c:2459`)
  documents the LUT layouts:
  - **Gen3 Capella-1/2 (8700/9700)**: indexed LUT — index to `0xC9C[7:0]`,
    data at `0xC98`; 256 × 32-bit entries; `[0]` enable, `[1]` NoSnoop,
    ReqID in `[19:4]`.
  - **Legacy 8000**: NT-Link LUT base `0xDB4`, NT-Virtual base `0xD94`;
    32 × 16-bit entries, `[0]` enable, `[1]` NoSnoop, ReqID `[15:0]`;
    older 8500/8600 NT-Virtual: 8 × 32-bit, enable `[31]`, NoSnoop `[30]`.
- **NT samples**: `Samples/NT_Sample/NTSample.c` (connects
  NT-Virtual↔NT-Link, adds host ReqID to the LUT), `NT_LinkTest`,
  `NT_DmaTest` (adds the DMA engine's ReqID to the LUT,
  `PlxDmaPerf.c:152-157`) — all in the public repo
  ([xiallc mirror](https://github.com/xiallc/broadcom_pci_pcie_sdk)) and in
  the v8.23 installer.
- **ALUT**: four LUT RAM arrays exposed as pseudo-ports
  `PLX_FLAG_PORT_ALUT_0..3 = 190..193` (`Include/PlxTypes.h:386-389`);
  EEPROM/SBR port-field encodings for ALUT: Draco `[15:10]=10_00xxb`,
  Capella-1 `10_11xxb` (`Samples/PlxCm/MonCmds.c:4337-4366`).
- **No Atlas-specific NT support exists in the open tree**: the SDK's NT
  path covers Gen3 families; on Atlas, NT is a synthetic-mode personality
  (`SYNTH_NT`/`SYNTH_TWC`, Q2) configured by the switch FW — no public
  ALUT/BAR-translation register map. UNKNOWN (gated docs only).
- **Mainline Linux: no Atlas NTB driver.** The lkddb driver database binds
  1000:c010/c012 to *no* driver and 1000:00b2 only to `mpt3sas`
  ([lkddb 6.16 list](https://raw.githubusercontent.com/linuxhw/Drivers/master/kernel/lkddb-6.16.list));
  Sourcegraph finds zero `1000:C010` references in the kernel or
  linux-firmware. Mainline `ntb_hw_*` covers Switchtec/AMD/Intel/IDT only.
  No out-of-tree Linux NTB-framework driver for Atlas found; Broadcom's NT
  support is the proprietary SDK driver + user-space API (and Windows
  driver).

## Q6 — Persistence of VS/NT/multi-host config

**Mostly answered at the mechanism level.**

- SBR is the *only* on-chip config persistence for base mode; all bifurcation
  is SBR-resident; chip cannot run without SBR (KCORES,
  [oshwhub](https://oshwhub.com/malong/pex88048gen4evm); Chiphell
  [2685098](https://www.chiphell.com/thread-2685098-1-1.html)).
- **Multi-image SBR selection exists in the wild**: newer Chinese boards
  carry "1 image per flash chip (aka per valid dip switch config)" written
  "with the management link", DIP selects which SBR image boots ([L1T
  AllenLYTC3249, post 4082058](https://forum.level1techs.com/t/171428/995));
  DIP-switch bifurcation cards (88048/88096) on AliExpress/ebay ([L1T post
  4037483](https://forum.level1techs.com/t/171428/902)); Taobao vendors flash
  per-order "Firmware Modes" (5x16/10x8/20x4, 12x4/6x8/3x16) ([L1T post
  4016826](https://forum.level1techs.com/t/171428/862)); Serial Cables Atlas3
  CLI has `setmode 0..5` / `showmode` + J9 strap selecting among ≥6 baked
  modes ([Atlas3 manual](https://serialcables.com/vendor-media/extra/upload/media/studio_680f727008ea27417341745846400.pdf?title=User-s%20Manual&proId=219)).
- **Flash hardware/tooling (SDK + Meta source)**: Atlas uses **SPI flash,
  not I2C EEPROM** — controller regs at PCI-view `0x001C0000` / AXI-view
  `0x2A0C0000`, CS0 memory window `0x00300000` (PCI) / `0x10000000` (AXI),
  256 B pages, 64 MB map (`PlxApi/SpiFlash.c:89-106`); PlxCm commands
  `spi`/`spi_erase`/`spi_file` (`MonCmds.c`); during flash update the
  on-chip "Maverick" CPU is held in reset via `PEX_REG_HOST_DIAG`
  (`PlxApiDirect.h:85,124-125`). Meta's OpenBMC library records **FW regions
  at flash `0x80000` and `0x200000`** with header pointer +0x38, active flag
  +0x3C, version +0x1C, FW size +0x30, XML size +0x278, and SBR/Main/MFG
  version CSRs at `0x6080020C/10/14`
  ([facebook/openbmc pex88000.c/h](https://github.com/facebook/openbmc));
  OpenBIC adds `BRCM_REG_SBR_ID 0xFFF00008` and `BRCM_REG_FLASH_VER
  0x100005F8` ([facebook/OpenBIC pex89000.c](https://github.com/facebook/OpenBIC)).
- **Flash layout/tooling**: Broadcom `g4xflash` (Linux/Windows/EFI shell)
  works with named regions — "Boot/SBR, Firmware, Config, and Log", each with
  primary & alternate copies; e.g. `g4xflash -i 1 erase -r 0 -s` ([L1T post
  3506886](https://forum.level1techs.com/t/171428/60)). So flash = SBR
  region(s) + synthetic-FW region + config + logs — matching the two boot
  modes (Q3).
- Vendor SBR authoring flow: PDE (from the SDK) flash tool, start offset
  **0x400**, block size **0xB30**, open dump as device "**C010**", edit `soc
  settings` → `STRAP_STNx_PORTCFG`, save, write back; in-system write needs a
  Gen4 x16-capable slot link; offline via CH341A-class programmer with 1.8 V
  adapter (Chiphell 2685098). Editing 88-series SBR requires a per-family
  **license key** in the SDK (KCORES: "你有87系列的授权，是不能配置88系列的").
- **How VS config gets baked (mechanism analog, Gen3 EEPROM format)**: the
  SDK's EEPROM writer documents a "register-write record" format with a
  6-bit port-class field; one class is literally **"VS Mode S%dP0" — VS
  station-specific pseudo-ports** (`11_0xxxb`), alongside NT-Virtual/NT-Link
  and ALUT-RAM classes (`Samples/PlxCm/MonCmds.c:4186-4480`). That is exactly
  how Gen3 chips bake VS/station register writes into their boot EEPROM —
  the Atlas PSB record space (team's 20-bit dword addressing) is the Gen4
  analog. So baking VS station config into boot media IS a vendor-designed
  mechanism, even if Atlas's own record classes aren't publicly enumerated.
- Whether **VS/multi-host** config can be baked on Atlas: no SBR VS fields
  exist (team audit); the vendor-intended persistent multi-host flow is the
  **synthetic FW image** (fdl fw / g4xflash Firmware region), which boots the
  embedded CPU and synthesizes VS/NT state from flash-resident config.
  **Confirmed in vendor-ECO wording**: Broadcom's MegaRAID changelog lists
  "Atlas-1 **VSFW**" (virtual-switch firmware) with SBR interaction tests
  and "Atlas2 ... **Multi host flash boot: create synthetic hierarchy**"
  ([Lenovo RAID 930-x changelog](https://linux.lenovo.com/yum/2024_05/ST558_7Y15_7Y16/RHEL9.3/documents/7Y37A01086_change_history.html)).

## Q7 — Document locations

**Doc IDs confirmed to exist** (Broadcom support-portal search index,
[knowledge article 234074](https://knowledge.broadcom.com/external/article/234074/broadcom-semiconductor-and-infrastructur.html),
verbatim index terms):

- `pex88000-rm108`, `pex88000-rm109` — register/hardware manuals (RM109
  exists! also RM108)
- `pex88000-pg114` — programming guide
- `pex88000-89000-pcie-sdk-ug100` — SDK user guide covering BOTH families
- `pex88000_guides` — guides bundle
- `pex880xx-sb-sign-an102` — secure-boot signing app note
- `pex88032-ds`, "pex88048b0 rdk", "pex88032 data sheet"
- `pex device editor`, `pex python sdk`, `pex sdk` — tooling entries
- Capella: `pex89000-g5-serdes-ug100`, `pex89048-ds102`, `pex89072-ds106`
  (incl. `pex89072-ds106.pdf`), `pex89144-ds107`, `pex89144-rdk`,
  `pex8900-pcie-gen5-wp100`, `pex89xxx-sb-sign-an100/an102`,
  `pex89000_ballmap_pinlist-220504`
- Curiosity: `pex87xx_error_injection_20may14_v1.4_capella1.pdf` — a 2014
  PEX87xx doc already carrying the "capella1" name (consistent with the SDK
  family enum, which calls the Gen3 8700/9700 chips "Capella-1/2" — see Q10
  for the naming caveat).

**Additional real document filenames**, cited in the comments of Meta's
OpenBIC drivers ([facebook/OpenBIC](https://github.com/facebook/OpenBIC)
`common/dev/pex89000.c:18-19`, `pex90144.c:18-19`):

- `PEX89000 Hardware I2C Slave UG_v1.0.pdf` — the I2C slave interface user
  guide (its command format is implemented in that driver!)
- `PEX89000_RM100.pdf` — the PEX89000 register manual (RM100 numbering)
- `pex90144_RM100.pdf` — PEX90144 register manual

**Documents shipped inside the public SDK** (xiallc repo `Documentation/`):
`PlxSdkUserManual.pdf`, `PLX_LegacyAPI.pdf`, `PLX_SDK_General_FAQ.pdf`,
`PLX_SDK_Release_Notes.htm`, `PLX_SDK_Linux_Release_Notes.htm`,
`PlxRdkReferenceGuide.htm`, `PLX API DLL with Visual Basic.htm`. Release
notes (through SDK 9.00) record: *"Added Support for PEX 89000 Devices"*
(drivers+API+PlxCm, SDK 9.00); *"Add Serial Debug Port (SDB) and MDIO access
native API support for PEX 88000 devices"*; *"Add native API support for I2C
for PEX 88000 devices"*; *"[PDE GUI] Updated Databook register table
information for Capella-1 devices 8796…"*; *"Updated NT LUT add API to
support newer LUT index access method Capella-1 & 2 devices"*. The PDE GUI
("PEX Device Editor") owns the `.db` databooks and the SBR editor.

**Negative results**: no public mirror of the PDE `.db` files exists —
`C010.db`, `AtlasSBR`, `pex_device_atlas`, `STRAP_FANOUT_EN`, `PEX88096`,
`VS0 Upstream` all return zero matches in global Sourcegraph code search;
the only public Atlas code in existence is the SDK mirrors
(xiallc 9.81, d4ddi0/PlxSdx 8.00, DaiZhiyuan/PlxSdk), facebook/openbmc
`pex88000.c/h`, facebook/OpenBIC `pex89000.c`/`pex90144.c`, and
mithro/plxtools.

**Access status: all of the above are portal-gated.** Anonymous probes to
`docs.broadcom.com/{doc,docs}/<id>` for every ID above return 404 (verified
2026-07-30); the support portal requires myBroadcom login, and the community
confirms 88/89-series docs are NDA (KCORES: "PEX88系列目前博通还没解禁，属于
NDA状态"). The SDK download page itself now shows a login wall
([broadcom.com software-dev-kits](https://www.broadcom.com/products/pcie-switches-retimers/software-dev-kits)).

**Publicly accessible right now (verified):**

- **Broadcom PCI/PCIe SDK v8.23 installer** (Windows, 114 MB, HTTP 200, no
  login): <https://docs.broadcom.com/docs-and-downloads/plx-files/Broadcom_PCI_PCIe_SDK_v8_23_Final_2020-11-18.exe>.
  Contents confirmed by filename scan: `AtlasSBR.db`, `PDE - 88000` /
  `PDE Chip Support\88000`, `Atlas_PEX88000`, Documentation folder
  (`PLX_LegacyAPI.pdf`, `PLX_SDK_General_FAQ.pdf`,
  `PLX_SDK_Release_Notes.htm`, `PDE_Linux_Release_Notes.txt`,
  `PlxGenMon.chm`), full PlxApi/PlxCm/PlxEep/SpiFlash source, NT samples,
  SDB (`SdbComPort.c`), I2C-via-Aardvark (`Aardvark.c`, `I2cAaUsb.c`),
  `MdioSpliceUsb.c`, PDE_client/server JARs. Extraction is nontrivial
  (InstallShield 10.1 single-file; carved CAB only yields IKernel).
- GitHub mirrors of the SDK source:
  [xiallc/broadcom_pci_pcie_sdk](https://github.com/xiallc/broadcom_pci_pcie_sdk)
  — **full Linux source of SDK v9.81** (PlxApi incl. `I2cAaUsb.c`,
  `PlxApiDirect.c/h`, `SpiFlash.c`, `SdbComPort.c`, `MdioSpliceUsb.c`;
  kernel drivers PlxSvc + `Source.Plx8000_NT`; PlxCm; NT samples;
  `Documentation/` PDFs) — the single most valuable public artifact;
  release assets also include the Linux zip of 8.23 and the (unextractable)
  Windows 9.81 exe;
  [d4ddi0/PlxSdx](https://github.com/d4ddi0/PlxSdx) (SDK 8.00, older),
  [DaiZhiyuan/PlxSdk](https://github.com/DaiZhiyuan/PlxSdk) (older subset),
  [mithro/plxtools](https://github.com/mithro/plxtools) (has an Atlas serial
  CLI backend, Q9).
- Meta open-source drivers (register-level, independently written against
  NDA docs): [facebook/openbmc `pex88000.c/h`](https://github.com/facebook/openbmc)
  (Atlas I2C/SPI library, flash layout), [facebook/OpenBIC `pex89000.c`,
  `pex90144.c`](https://github.com/facebook/OpenBIC) (Atlas C010/C012 +
  Atlas2 C030 + PEX90144 C040 drivers; cite the RM100/I2C-UG doc names).
- Product briefs: PEX88000 family brief **BC-0484EN**
  ([docs.broadcom.com/doc/BC-0484EN](https://docs.broadcom.com/doc/BC-0484EN),
  [Mouser mirror PDF](https://www.mouser.com/datasheet/2/678/BC_0484EN_2019_07_17-3498215.pdf));
  full switch **selection guide BC00-0445EN** (July 2023, 30 pp, covers
  PEX89000/88000/9700/8700/8600 + bridges):
  [docs.broadcom.com/doc/BC00-0445EN](https://docs.broadcom.com/doc/BC00-0445EN).
- Serial Cables Atlas2/Atlas3 manuals (register-level CLI!):
  [Atlas2 ITAP PDF](https://serialcables.com/vendor-media/extra/upload/media/studio_672b8f6ce98be8794561730911612.pdf?title=User%27s%20Manual&proId=74),
  [Atlas3+Atlas2 PDF](https://serialcables.com/vendor-media/extra/upload/media/studio_680f727008ea27417341745846400.pdf?title=User-s%20Manual&proId=219).
- OSHWHub open-hardware projects with full schematics + base SBR firmware
  (attachments need free 立创EDA login):
  [PEX88096 GPU底板](https://oshwhub.com/malong/pex88096-pcie4-switch-gpu-basepl),
  [PEX88048 8×M.2 EVM](https://oshwhub.com/malong/pex88048gen4evm),
  [PEX88064 6×SlimSAS](https://oshwhub.com/eda_nrhnxjzuv/kcores_pex88064_aic_gen4_6slimsas);
  full design notes mirrored at [bilibili cv39904570](https://www.bilibili.com/read/cv39904570/).
- Bressner 8-slot Gen4 backplane datasheet (PEX88096, "DMA controller, SSC
  isolation, 150 ns"):
  [shop.bressner.de PDF](https://shop.bressner.de/datenblatt/8-Slot-PCIe-Gen4-x8-Datasheet.pdf).
- **Lenovo ThinkSystem 1611-8P** (PEX88048-based switch card,
  [Lenovo Press LP0761](https://lenovopress.lenovo.com/lp0761.pdf)): firmware
  is **publicly downloadable from Lenovo** (no Broadcom portal) — download
  page [DS552120](https://support.lenovo.com/us/en/downloads/ds552120-thinksystem-1611-8p-nvme-switch-card-firmware-for-anyos);
  package names from Lenovo's Best Recipe tables:
  `lnvgy_fw_nvmeswitch_pex.1611.8p-125.3.4.0-2_linux_x86-64.bin` (2021),
  `lnvgy_fw_storehba_mpt3.nv.ubm-125.07.00.00-0_anyos_noarch.uxz` (2023-2025)
  ([HT513172](https://support.lenovo.com/fr/fr/solutions/ht513172-lenovo-scalable-infrastructure-release-21c-best-recipe),
  [HT517400](https://support.lenovo.com/kr/ko/solutions/ht517400-lenovo-everyscale-release-24b1-best-recipe)).
  Note the channel naming: first `nvmeswitch_pex`, later `storehba_mpt3.nv.ubm`
  — i.e. Lenovo flashes it through the **MPT3 / UBM (SFF-TA-1005 Universal
  Backplane Management)** path, and Lenovo's standard **MPT3.5 Windows HBA
  driver lists "1611-8p NVMe Switch" as a supported device**
  ([DS566795](https://support.lenovo.com/ae/zc/downloads/ds566795-lenovo-storage-host-bus-adapter-hba-windows-driver)).
  Direct download.lenovo.com paths are JS-obfuscated (403/404 on guessed
  URLs) but retrievable via the DS552120 page in a browser.
- 同泰怡 TTY TG657V2 server manual (ships an "88096计算模块"; §3.9 DIP-switch
  table — extraction incomplete, strong lead):
  [ttyinfo.com PDF](https://www.ttyinfo.com/Uploads/Temp/support/20260515/6a06b89ab50ca.pdf).
- Older-family public design docs prove Broadcom *can* publish these:
  [PEX8648 Hardware Design Checklist](https://docs.broadcom.com/doc/PEX8648_Hardware_Design_Checklist_24Oct2008.pdf),
  [PEX_8609 errata](https://docs.broadcom.com/doc/PEX_8609_Errata_v1.9_4May12.pdf)
  — nothing equivalent public for 88000.

## Q8 — Field reports (concrete details)

Level1Techs "A Neverending Story" megathread
([topic 171428](https://forum.level1techs.com/t/171428)) and STH:

- **Boards/vendors**: KCORES (OSHWHub), 39com, CWWK (~$230 PEX88048,
  [cwwk.net listing](https://cwwk.net/products/changwang-cwwk-microcontroller-broadcom-88048-pcie4-0x16-accessory-supports-8m2-underdrive-free-split-high-bandwidth-stable-expansion)),
  LinkReal/LR-Link LRNV9F48 (= Broadcom P411W-32P clone,
  [post 3980281](https://forum.level1techs.com/t/171428/755)), ADT-Link
  (10×SFF-8654 PEX88096), ServerHive, Maicun/MIwin (PEX89144 backplanes,
  [post in topic 245618](https://forum.level1techs.com/t/creating-a-pcie-bifurcation-solution-for-ai-councils-the-official-thread-of-the-video/245618)).
  Price datapoints: PEX88096 boards $250–950, PEX89144 13×x16 Gen5 ~$2860
  ([post 4016826](https://forum.level1techs.com/t/171428/862)).
- **Broadcom P411W-32P** (first-party host card): FW 4.1.2.1 image structure
  with SBR Bootloader + Config Pages + Signed Block
  ([post 3921885](https://forum.level1techs.com/t/171428/712)); Windows
  driver signature breakage and Win11 22H2 BSODs ([post
  3695735](https://forum.level1techs.com/t/171428/304)); ASPM disabled in
  firmware, vendor says not changeable
  ([post 3980595](https://forum.level1techs.com/t/171428/757)); lspci shows
  upstream bridge as **Port #200**, downstream ports 0..N, "ASPM not
  supported" on all switch ports ([post
  3980281](https://forum.level1techs.com/t/171428/755)); flashing via
  **g4xflash** with region numbers ([post
  3506886](https://forum.level1techs.com/t/171428/60)).
- **Image patching without license**: AllenLYTC3249 runs an asymmetric
  x8x8+x4x4x4x4 config on a 39com PEX88048B0 by dumping all SPI images and
  binary-diffing/patching them ("checksums are a thing to deal with";
  SpiFileLoad vs EEpromFileLoad = newer vs older boards), using Broadcom's
  public SDK + PlxCm GPL driver + a [kernel-5.8+ fixups
  patch](https://forum.level1techs.com/uploads/short-url/1diDzhhI18PuR5eiwOrQZgQ575i.patch)
  ([posts 4060320](https://forum.level1techs.com/t/171428/962),
  [4082058](https://forum.level1techs.com/t/171428/995)).
- **PEXDeviceEditor**: Broadcom's flash editor is used by Chinese forum
  members, but without (license/unlocked device) the UI is greyed out ([post
  4075844](https://forum.level1techs.com/t/171428/990)) — matches the
  per-family license-key requirement.
- **SerialCables PCI4-AD-x16HE-BG4** (4×4 external switch, Atlas + MCU):
  full saga in [STH 47497](https://forums.servethehome.com/index.php?threads/help-with-serialcables-com-pci4-ad-x16he-bg4.47497/)
  — `fdl sbr|fw|cfg|mfg|mcu` over USB-C CLI with XMODEM; v1.1 vs v1.2
  hardware behave differently; base 4x4 image `B0 HOST_X4_SRIS_V02.bin`;
  exposes **/dev/mpt3ctl + SES device**; jumpers for target mode + "PCI-SIG"
  position enabling Gen4 card-to-card links; Broadcom OEM tools **xutil /
  xflash** mentioned in firmware XML comments (UART CN2); custom cable pinout
  (A:0+3, B:1+2); SFF-8644 cables leave clock pins unwired (EEPROM in
  housing) → red LED, no link.
- **GPU compute use works well**: Panchovix's cascaded PEX88096+PM50100 +
  7-GPU AM5 builds with P2P ([post 4043624](https://forum.level1techs.com/t/171428/929);
  topology dumps [post 4038488](https://forum.level1techs.com/t/171428/907));
  STH thread 52488: $500 88096 board, 45–50 W, auto power on/off with host
  presence, 4×3090 llama.cpp, P2P ~52 GB/s bidir writes, ~1 µs P2P latency
  with [aikitoria/open-gpu-kernel-modules](https://github.com/aikitoria/open-gpu-kernel-modules)
  ([STH 52488](https://forums.servethehome.com/index.php?threads/new-chinese-pcie-switch-board-gpu-testing.52488/)).
  Board ships all-x16, "doesnt dynamically reconfigure itself" — per the
  same thread.
- Consumer-board gotchas: BAR/MMIO exhaustion (ASRock X870 "MMIO limit 4T"
  fixes 8×B60 boot, [post 4097814](https://forum.level1techs.com/t/171428/1016));
  D4 boot codes on Maxsun; "pcie insertion function" required in slot
  adapters ([post 4084361](https://forum.level1techs.com/t/171428/1000)).
- Chiphell 2685098: KCORES 88096 card works on X570 and even a PCIe 2.0 x1
  Q77 slot; 75 cm SFF-8654 cable margin OK; power/thermal warnings (88048
  VDD09 18.12 A; 88096 ~35 W half-load) — matches family table 35.78 W typ.

## Q9 — Management / out-of-band interfaces

- **In-band management endpoint**: PCI **1000:00b2** "PCIe Switch management
  endpoint" (class: SAS controller), bound by mainline **mpt3sas** —
  `mpt3sas_base.h`: "/* Atlas PCIe Switch Management Port */
  #define MPI26_ATLAS_PCIe_SWITCH_DEVID (0x00B2)"
  ([mpt3sas_base.h](https://raw.githubusercontent.com/torvalds/linux/master/drivers/scsi/mpt3sas/mpt3sas_base.h),
  [lkddb](https://raw.githubusercontent.com/linuxhw/Drivers/master/kernel/lkddb-6.16.list)).
  Speaks MPI26: config ext-page type 0x1C = PCIe Switch pages
  (`Mpi26PCIeSwitchPage0/1`, per-port width/rate, retimer presence),
  topology events `MPI26_EVENT_PCIE_TOPO_SS_*`
  ([mpi2_cnfg.h](https://raw.githubusercontent.com/torvalds/linux/master/drivers/scsi/mpt3sas/mpi/mpi2_cnfg.h)).
  Subsystems seen: Supermicro AOM-PCIE5-418P, **Lenovo ThinkSystem 1611-8P
  PCIe Gen4 NVMe Switch Adapter** (pci.ids). Userspace handle: /dev/mpt3ctl +
  SES enclosure device (STH 47497). This is the most promising Linux-native
  management channel.
- **I2C slave (documented in SDK + Meta code)**: the switch answers on
  auto-probe ranges `0x38-0x3F, 0x58-0x5F, 0x68-0x6F, 0x70-0x77, 0x18-0x1F`
  (7-bit; `I2cAaUsb.c:555-563`, default 100 kHz); real-world address on a
  Meta PEX89144 board: `0x59` (I2C0) / `0x61` (OpenBIC at-cb platform).
  Command format: Atlas-1 uses
  `|Resvd|I2C_Cmd|R|Mode|StnSel|PtSel|R|Byte_En|DW_Offset|` with Mode 0
  (ports 0-63) / Mode 2 full-address (switched via port-0 reg `0x2CC` —
  OpenBMC writes `03 00 3C B3 00 00 00 07`, i.e. reg 0x2CC ← 7);
  **Atlas2 has no modes — the 22-bit register address rides in the command**
  (`I2cAaUsb.c:135-204`; Meta's byte layout in OpenBIC `pex89000.c:64-123`:
  byte0 cmd read=0b100/write=0b011, PEX90144 read=0b111). The gated doc
  defining this is `PEX89000 Hardware I2C Slave UG_v1.0.pdf` (Q7).
- **Chime→AXI index bridge** (reach any AXI address via I2C/SDB):
  `0x1F0100` ADDR / `0x1F0104` DATA / `0x1F0108` CTL, CTL `[0]`=write,
  `[1]`=read, `[3]`=read-valid (`ATLAS_REG_IDX_AXI_*`,
  `PlxApiDirect.h:110-121`; OpenBIC same, but **PEX90144 moved it to
  `0x3F0100/04/08`**).
- **SMBus**: Chime SMBus master regs `0xFFE00004/08/0C/10`
  (WR_CMD/WR_DATA/RD_CMD/RD_DATA) — used by Atlas2/90144 for temperature
  (OpenBIC `pex89000.c:47-50`; sensor at 0x17 on 90144).
- **Serial consoles**: `SDB_RX/TX` (PLX serial-debug port; SDK `SdbComPort.c`
  talks it; card jumper J6 routes MCU↔SDB) and `UART_RX/TX` (data UART,
  "require Atlas2 FW support"); baud via **MODE_SEL2** (low=115200,
  high=19200) — KCORES pin notes + [Atlas2 manual p.3](https://serialcables.com/vendor-media/extra/upload/media/studio_672b8f6ce98be8794561730911612.pdf?title=User%27s%20Manual&proId=74).
  **SDB wire protocol** (`SdbComPort.h:90-96`): `'G'` read, `'N'` read-next,
  `'P'` write, `'\n'` terminator, `'%'` ACK, `'E'` error, init `"%\n"`;
  4-byte BE address + 4-byte BE data. SDK release notes: SDB/MDIO native
  API support added explicitly for PEX 88000.
- **MDIO** via Splice USB (`PlxApi/MdioSpliceUsb.c`, 100 kHz): full Atlas
  AXI map — PBAM `0x2A000000` (UART +0x50000, I2C +0x60000, SPI +0xC0000,
  GPIO/GPT/SGPIO/PWM/TRNG/APSHA/SRK), PSB `0x60000000`, **PEX ports
  `0x60800000`** (matches the Serial Cables `dr`/`mw` window), OCM
  `0x64900000/0x64940000`, PSW0-5 SerDes `0x70x00000`, CCR blocks
  (Efuse `0xFFE7E000`, Watchdog `0xFFE80000`, CCR `0xFFF00000`), plus a
  "Secure Boot ROM" window `0x29C00000` (commented out).
- **MCU CLI** (Serial Cables cards, USB-C CN6, 115200 8N1):
  `fdl sbr|fw|mcu`, `lsd` (sensors), `mw`/`dr` (32-bit register write/read —
  examples use CSR window at **0x60800000**), `dp <port>` (per-port dump,
  ports 0–47), `df` (flash dump, examples at **0x400** = SBR offset —
  cross-confirms the known container location), `ssdrst` (300 ms PERST#),
  `pwrdis`, `hled`, `showport` (USP/DSP link status; mentions **DPR =
  Dynamic Port Reconfiguration**, "configures Gen5 x1 for 16 lanes in MCIO
  ports 0 to 15" — expands the SBR "Station DPR enable" field), `bist` (I2C
  scan), `spread` (SSC 3000/5000 PPM), `clk` (port clock gating), `itap`
  (**iTAP = "embedded PCIe analysis support"** — Broadcom's on-die PCIe
  analyzer mode; while enabled, showport/FW-version reads fail), `iicwr`/
  `iicw` (SMBus to drives, e.g. slave 0xd4), `ver`, `sysinfo`, `reset`
  ([Atlas2 manual p.11-27](https://serialcables.com/vendor-media/extra/upload/media/studio_672b8f6ce98be8794561730911612.pdf?title=User%27s%20Manual&proId=74)).
  A third-party implementation of this card CLI exists in
  [mithro/plxtools](https://github.com/mithro/plxtools)
  (`src/plxtools/backends/serial.py`, `devices/definitions/pex880xx.yaml`:
  "Serial Cables ATLAS HOST CARD" on `/dev/ttyACM0` @ 9600 baud, commands
  `dr`/`mw`/`df`/`ver`/`lsd`/`showport`) — directly reusable by pexctl.
- **I2C**: six buses `I2C_SCL0-5/SDA0-5`, open-drain, 2 kΩ pull-ups to 1.8 V;
  bus 2 dedicated to **SHPC** hot-plug with `SHPC_INT#`; switch-side
  `ATLAS_SCL/ATLAS_SDA` are routed onto MCIO sideband pins A11/A12 (KCORES;
  Atlas2 manual p.5-7).
- **Management Ethernet**: full **RGMII** interface ("和服务器的BMC的管理网口
  是一样的" — like a BMC port), plus JTAG (TCK/TDI/TDO/TMS/TRST_L),
  GPIOA0-31 (SBR-defined), SGPIO0 (KCORES notes).
- **Dedicated management PCIe x1 ports**: lanes 96/97 (PET96/97, PER96/97) on
  88096, 48/49 on 88048
  ([oshwhub 88096 page](https://oshwhub.com/malong/pex88096-pcie4-switch-gpu-basepl),
  bilibili cv39904570).
- **iTAP / PEA**: the manuals' `itap` command ("Set iTAP mode enable",
  "embedded PCIe analysis support") is Broadcom's **PEA (PCIe Embedded
  Analyzer)** on-die analyzer, tapped via SerialTek **iTAP Panda** hardware —
  stated on Serial Cables' Gen5 card page
  ([serialcables.com PCI5-AD-x16HI-BG5](https://www.serialcables.com/product/pcie-gen5-x16-mcio-host-card-with-atlas2-b0-pcie-switch/)).
- **Recovery hooks**: J9 "sbr mode sel" strap (Atlas3) forces base mode;
  MODE_SEL1 high disables SBR load; external flash programming needs 1.8 V
  (CH341A + level shifter); `SYS_ERROR#` asserts on bad SBR (KCORES).
- Broadcom OEM field tools **xutil/xflash** exist (firmware XML comment, STH
  47497 post #6) — not publicly distributed.

## Q10 — PEX89000 (Capella) transferability

- **Naming caveat (matters for searching)**: in the SDK family enum
  (`Include/PlxTypes.h:330-352`) "**Capella-1/2**" are the *Gen3* 8700/9700
  chips; Gen4 PEX88000 = `PLX_FAMILY_ATLAS` (C010/C011/C012); Gen5 PEX89000
  = `PLX_FAMILY_ATLAS_2` (C030) and `ATLAS2_LLC` (C034). Meta's code agrees
  (`pex_dev_atlas1/2`). Broadcom *marketing* calls PEX89000 "Capella" (the
  brief's usage), and a 2014 PEX87xx doc already carried "capella1". When
  mining sources, search BOTH "Capella" (Gen3 or Gen5 depending on era) and
  "Atlas2" (Gen5).
- **Codename ladder (press evidence)**: Atlas = PEX88000 (Gen4) → **"Atlas2"
  = PEX89000 (Gen5)** — Serial Cables' Gen5 host cards are sold as "Broadcom
  **Atlas2** Production Level LLC PCIe Switch ... Based on Broadcom's new
  **PEX89000** PCIe switch chip"
  ([serialcables.com Gen5 card](https://serialcables.com/product/pcie-gen5-x16-mcio-host-card-with-atlas2-b0-pcie-switch/))
  → **"Atlas3" = PEX90080 (Gen6)**, 64 lanes, production B0 silicon
  ([Serial Cables Gen6 launch, Apr 2026](https://www.desmoinesregister.com/press-release/story/66706/serial-cables-launches-pcie-gen6-host-adapter-card-with-broadcom-atlas3-b0-production-silicon/)).
  Note Serial Cables' *card* names ("Atlas2 ITAP card" = Gen4, "Atlas3 card"
  = Gen5) are offset by one from Broadcom's *chip* codenames — the "Atlas3
  card" manual still calls the chip "Atlas2 switch", i.e. PEX89000. The
  synthetic-vs-base boot-mode pair, `fdl sbr`/`fdl fw` split, and numbered
  SBR modes (`setmode 0..5`, per-port width+clocking) therefore exist on
  Capella with the same structure as Atlas — strongest available evidence of
  SBR/VS model transferability.

- Same virtual-port model: pci.ids **1000:c030 = PEX890xx**, with subsystems
  "PEX89024/89032/89048 ... **Upstream/Downstream Port**" — the same
  synthesized USP/DSP device scheme as Atlas's 1000:100b ([mageia pci.ids
  diff](https://gitweb.mageia.org/software/ldetect-lst/diff/lst/pci.ids?h=0.6.39&id=a6388bcd1296598800b860fde91816ef7e8f3cae),
  [pci-ids.ucw.cz](https://pci-ids.ucw.cz/v2.2/pci.ids)). *INFERRED*: the VS
  architecture (virtual switches with virtual ports, synthetic mode, gDMA/
  TWC-NT endpoints) transfers.
- **Structural continuity in code**: the VS register block (0x354/0x358/
  0x360+i*4/0x380+i*4/0x3A0) is shared Cygnus → Draco → Capella-1/2 (Gen3) →
  Atlas, and Atlas2 (C030/C034) shares the Atlas CCR map plus extensions
  (extra clock-enable regs `0x318/0x324` for ports 96-143,
  `ATLAS2_REG_CCR_UPSTREAM_PORT` CCR `0x1A4`) — the Atlas VS layout is the
  Gen3 layout widened for more ports. Meta's `pex89000.c` drives Atlas C010/
  C012 and Atlas2 C030 with the *same* code. PEX90144 (144-lane Gen5,
  device **C040**) is the same architecture with the Chime index bridge
  moved to `0x3F0100` (OpenBIC `pex90144.c`).
- Chip-ID correction: the `a024/a032/a048/a064/a080/a096` values are not
  just subsystem IDs — they are Atlas's **internal Chip IDs by lane count**
  (`PlxApi.c:1694-1845`, read from a VSEC-adjacent register); Atlas2 SKUs
  use a different scheme (`0x0072/0x0048`, `0x0088/0x0064`, `0x0104/0x0080`,
  `0x0136`, with "HW errata on Atlas2 A0" duplicate IDs, `PlxApi.c:1846-1971`).
- Feature deltas ([BC00-0445EN](https://docs.broadcom.com/doc/BC00-0445EN)):
  Capella = 24–144 lanes (PEX89024…89144), 115 ns, **8 NT ports** (big
  chips) / 4 (89024/32/48) vs Atlas 12–48, **Dual Core ARM A15** vs Cortex
  R4, SRIS/SRNS/CIKS, Shared I/O, DPC/Read Tracking; Gen5 SerDes has its own
  gated UG (`pex89000-g5-serdes-ug100`).
- **Synthetic mode exists on Capella too**: Lenovo firmware changelog "PEX
  89000: synthetic mode BST for B0 board" ([lenovo.com change
  history](https://linux.lenovo.com/yum/2024_05/ST558_7Y15_7Y16/RHEL9.3/documents/7Y37A01086_change_history.html))
  — and Lenovo ships Capella FW through its Linux YUM/LVFS channels (firmware
  artifacts obtainable without Broadcom portal!).
- One SDK covers both: doc `pex88000-89000-pcie-sdk-ug100` is a single user
  guide; xiallc's SDK mirror "Added Support for PEX 89000"
  ([releases](https://github.com/xiallc/broadcom_pci_pcie_sdk/releases)) —
  VS/multi-host concepts are documented once for both families (in the gated
  PG/RM docs).
- Capella docs are NOT more available in practice: portal lists more Capella
  artifacts (datasheets DS102/DS106/DS107, ball-map/pin-list, WP100 white
  paper, RDK docs) but all gated; Chinese community confirms nothing
  circulating and begs for leaks (KCORES).

## SURPRISES / LEADS

1. **Full SDK v9.81 Linux source is public on GitHub**
   ([xiallc/broadcom_pci_pcie_sdk](https://github.com/xiallc/broadcom_pci_pcie_sdk))
   — not just an old mirror: Atlas register constants (`PlxApiDirect.h`), the
   VS/multi-host code (`I2cAaUsb.c`), SPI-flash driver, SDB/MDIO/I2C
   backends, NT driver (`Source.Plx8000_NT`), PlxCm, NT samples, and the
   Documentation PDFs. This alone answers Q2/Q3/Q5/Q6/Q9 at register level.
2. **Meta ships register-level Atlas/Atlas2/PEX90144 drivers** in
   [facebook/openbmc](https://github.com/facebook/openbmc)
   (`common/recipes-lib/pex/files/pex88000.c/h`) and
   [facebook/OpenBIC](https://github.com/facebook/OpenBIC)
   (`common/dev/pex89000.c`, `pex90144.c`) — flash layout, version CSRs,
   I2C command byte layouts, CCR system-error bits (incl. `SBR_LOAD_FAIL`),
   Chime index bridge — written against NDA docs (`PEX89000_RM100.pdf`,
   `PEX89000 Hardware I2C Slave UG_v1.0.pdf`) whose *contents* therefore
   leak through this code.
3. **Public, no-login Broadcom SDK installer**: the v8.23 exe URL (above) is
   live on docs.broadcom.com — contains Atlas SBR db, PDE 88000 support, NT
   samples, and docs. Neither 7z nor unshield can open the InstallShield
   10.1 InstallScript single-file (8.23 or the 9.81 exe from xiallc
   releases); needs Wine or `isx`-class tooling to liberate the PDE `.db`
   databooks — the last missing piece for Q1.
4. **mpt3sas is Atlas's management driver** — /dev/mpt3ctl + SES on any
   mainline kernel; MPI26 PCIe-switch config pages give per-port link state
   without any Broadcom SDK. Lenovo flashes the 1611-8P through this
   MPT3/UBM path; g4xflash's "official drivers" are likely this + PLX
   driver.
5. **pci.ids exposes the synthetic-mode device inventory** (virtual USP/DSP,
   TWC/NT2, gDMA, secure c012 variant) — gives pexctl concrete device IDs to
   detect synthetic vs base mode at runtime, and per-chip subsystem IDs
   (a024…a096) to identify exact die.
6. **Multiple SBR images per flash, DIP-selected** — explains both the
   "Firmware Mode: 5x16/10x8/20x4" Taobao listings and the DIP-switch cards;
   pexctl could implement the same multi-image trick.
7. **"Serial HPC: all ports"** on Atlas (selection guide) — every port has a
   serial hot-plug controller; plus SHPC over I2C bus 2.
8. **iTAP = Broadcom PEA (PCIe Embedded Analyzer)** tapped via SerialTek
   iTAP Panda hardware — an on-die PCIe analyzer mode worth probing (Q9).
9. **PEX88T32** (SS08-0B00-00) — a 32-lane Gen4 *retimer* sibling on the
   Atlas die family (retimer-only SKU).
10. **Gen6 exists**: PEX90080 "Atlas3", 64 lanes Gen6, production B0
    (Apr 2026) — the family is alive; docs/flows will keep evolving.
11. **Lenovo ships Atlas (PEX88048, 1611-8P) and Capella switch firmware via
    public channels** — package names and versions above (Q7); flashing runs
    over MPT3/UBM, and the stock MPT3.5 Windows driver supports the card.
    Lenovo ThinkSystem 1611-8P subsystem ID 1d49:0003 in pci.ids.
12. **TTY TG657V2 manual** (DIP-switch table §3.9 for a PEX88096 GPU module)
    — fetch with a better PDF pipeline; likely documents vendor DIP↔mode
    mapping.
13. Follow-ups not completed: extracting the v8.23/9.81 exes' PDE `.db`
    databooks (would settle Q1); OSHWHub attachment downloads (need 立创EDA
    account); enumerating github.com/KCORES repos; the eleok.com "pex88000
    sdk 许可证" cracking-forum lead (unverified); CSDN unreachable from this
    environment. All raw artifacts from this session (Serial Cables manuals,
    briefs, forum harvest, SDK download, pci.ids, mpt3sas sources) are
    cached under `/tmp/pex-research/`; the SDK agent's clones and extracted
    doc texts are under `/tmp/pex-sdk-research/` (both volatile /tmp).
