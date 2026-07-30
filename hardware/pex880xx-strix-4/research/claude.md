# PEX88096 "Atlas" research findings (agent: claude / Opus 4.8)

Scope: the 10 open questions from the shared brief. Compiled from five parallel
research sub-agents plus direct source reads (mainline kernel `switchtec.c`,
Level1Techs field thread, Broadcom KB 234074, `PlxSdk`, FreeBSD `ntb_hw_plx`,
Serial Cables Atlas host-card manuals). Every claim is cited. Anything not
publicly confirmable is marked **UNKNOWN**. The register-level truth for most of
these fields lives in Broadcom's NDA docs (`pex88000-rm109`, `pex88000-pg114`,
`pex88000-89000-pcie-sdk-ug100`); where that is the case I say so and give the
strongest defensible public inference instead of guessing.

> **Headline corrections / high-value leads (read first):**
> 1. **Atlas is NOT managed by the mainline Linux `switchtec` driver.** I read
>    the mainline `drivers/pci/switch/switchtec.c` device table directly: it
>    binds only Microsemi/Microchip `0x11f8` and EFAR `0x1fff` — **not** Broadcom
>    `0x1000:c010`. The widely-repeated blog claim ("the switchtec driver
>    enumerates the PEX88000 management endpoint") is **false**. Atlas has **no**
>    mainline management/NTB driver of any kind.
> 2. **The public `PlxSdk` fork positively identifies Atlas** (`PLX_FAMILY_ATLAS`
>    = chips C010/C011/C012) and leaks a real Atlas register map: AXI bases
>    (PSB `0x6000_0000`, PSW-SerDes `0x7000_0000`, PEX/GEP `0x6080_0000`, CCR
>    `0xFFF0_0000`), CCR mode reg `0xB0[1:0]` (0=Standard/base, 1=Fabric),
>    per-port Port-Type in CCR `0x120` (2 bits/port), VS0 upstream at `0x360`.
> 3. **The SBR *Port Type* field (SoC dwords 25–32, 2 bits/port) is almost
>    certainly the persisted form of CCR `0x120`** (also 2 bits/port). That is
>    the single best lead for decoding Q1.
> 4. **Out-of-band recovery is real and documented:** the Serial Cables Atlas MCU
>    CLI reads/writes the SBR directly — `df 0x400` dumps the SBR, `fdl sbr`
>    rewrites it — over a 115200 8N1 USB-CDC console, no host PCIe needed.

---

## Q1 — SBR "Port Type" (dwords 25–32) and "Clocking mode" (dwords 33–39) enums

**Exact 2-bit numeric tables: UNKNOWN publicly** (they live in `pex88000-rm109`
/ SBR programming reference, NDA). But there is a strong cross-reference and a
zero-consistent inference for each.

### Port Type — best lead: it mirrors CCR `PORT_TYPE0` at `0x120`
The public `PlxSdk` (`PlxApi/PlxApiDirect.h`, `.c`) shows Atlas has a runtime
per-port "port type" register: **`ATLAS_REG_CCR_PORT_TYPE0 = 0x120`**, decoded
**2 bits per port**, `offset = 0x120 + (portNum/portsPerStn)*4`,
`type = (reg >> ((stnPort%16)*2)) & 0x3`, with observed value **`0b01` = Fabric
port** (`PlxApiDirect.c` ~L2694). A 2-bit SBR "Port Type" field of the same
width almost certainly persists this same CCR field — so decoding one decodes
the other.
- The classic PLX port roles are: transparent-upstream, transparent-downstream,
  NT-Link, NT-Virtual (+ DMA, management/MPT). NT-Virtual and NT-Link "register
  sets are different" and take different Subsystem IDs — PLX *PEX 85XX EEPROM
  Design Note v1.1*
  (https://docs.broadcom.com/doc/PEX_8518_8517_8512_8508_EEPROM_Design_Note_v1_1_09Jul07).
- A 2-bit field selects only **four** of the ~seven roles → Port Type is a
  *coarse* per-port role selector; finer NT-Virtual/NT-Link/DMA/mgmt distinctions
  are set elsewhere (runtime "Port Configuration" CSR 0xc0–0xc2, and the VS0
  Upstream NT fields).
- **Defensible inference (UNCONFIRMED):** `0 = transparent/normal`
  (upstream-vs-downstream disambiguated by the dword-0 upstream-port index, not
  this field), `1 = Fabric/managed port` (matches the `0b01` CCR observation),
  `2`/`3` ∈ {NT-Link, NT-Virtual, DMA/management} — order **UNKNOWN**. This fits
  the observation that every fan-out reference image is all-zero: a plain fan-out
  switch has no NT/fabric ports, so every port is type 0.

### Clocking mode — 0 = common clock; {SRNS, SRIS, reserved} for 1–3
- PEX88000 supports **Common/CFC ("ClkS"), SRNS (Separate Refclk No SSC), SRIS
  (Separate Refclk Independent SSC)**, plus SSC isolation to mix domains
  per-port. Broadcom *BC00-0445EN* selection guide + *BC-0484EN* product brief
  (https://docs.broadcom.com/doc/BC00-0445EN,
  https://docs.broadcom.com/doc/BC-0484EN); retimer *PEX88T32-PB* explicitly
  "supports SRNS, SRIS, and common clock" (https://docs.broadcom.com/doc/PEX88T32-PB).
- Corroborated by the Serial Cables Atlas CLI: `spread` = "used for SRIS
  testing" (SSC on/off), `clk [en|dis]` = "used for SRNS or SRIS testing";
  refclk runs "CFC (spread off) or SSC." (Serial Cables Atlas2 manual, below.)
- **Defensible inference (UNCONFIRMED):** `0 = common/CFC` (the fan-out default —
  one on-board reference fanned to all downstream ports), `1–3` ∈ {SRNS, SRIS,
  reserved}. Exact assignment **UNKNOWN**.
- **UNKNOWN:** whether the per-port SRIS/SRNS/common select is *only* in the SBR
  Clocking field or also mirrored in a runtime CSR — the public SDK exposes only
  per-port *clock-enable* bitmaps (0x30C/0x310/0x314/0x318, `maxPorts=128`), not
  clock-architecture selects.

---

## Q2 — Virtual-switch programming model; VS1–3 vectors; VS1–3 Upstream encoding

The Atlas VS register block is the **legacy PLX 8000-series VS block, inherited
at the same offsets** (byte offset = dword×4). Confirmed against the
Broadcom/PLX SDK (`Driver/Source.PlxSvc/ApiFunc.c`) and the PEX87xx I²C model
(`github.com/benmcollins/pex87xx`, `examples/pex-status.c`):

| dword | byte | name | evidence |
|---|---|---|---|
| 0xd5 | 0x354 | Management Port Config | `ApiFunc.c:3021`, `pex-status.c:138` |
| 0xd6 | 0x358 | VS Enable (VS0–7 in [7:0]) | `ApiFunc.c:3024`, `pex-status.c:140` |
| 0xd8–0xdf | 0x360+i·4 | VS0..VS7 **Upstream** register | `ApiFunc.c:3068`, `PlxApiDirect.h` `ATLAS_REG_VS0_UPSTREAM 0x360` |
| 0xe0–0xe7 | 0x380+i·4 | VS0..VS7 **Downstream Port Vector** | `ApiFunc.c:3077`, `I2cAaUsb.c:1844` |
| 0xe8 | 0x3A0 | **VS Reset** (one bit per VS) | `ApiFunc.c:3234`, `I2cAaUsb.c:2000` |

### Where VS1–3 membership is set (resolves "no VS1–3 vector register")
In the PLX model **0xe0/0xe1/0xe2/0xe3 are four separate per-VS downstream port
vectors**, not one wide VS0 bitmap: VS0=0xe0(0x380), VS1=0xe1(0x384),
VS2=0xe2(0x388), VS3=0xe3(0x38c) … VS7=0xe7(0x39c). Moving a port between VSes
(`ApiFunc.c` `PlxMH_MigrateDsPorts`, ~L3205):
```c
PLX_8000_REG_WRITE(pdx, 0x380 + (VS_Source*4), vector_src); // clear bit in source VS
PLX_8000_REG_WRITE(pdx, 0x380 + (VS_Dest*4),   vector_dst); // set bit in dest VS
PLX_8000_REG_WRITE(pdx, 0x358, VS_EnabledMask | (1<<VS_Dest)); // enable dest VS
```
A port belongs to exactly one VS; the SDK clears the losing VS's bit before
setting the gaining VS's bit.

### The 98-bit / 4-dword ambiguity (honest caveat — needs silicon test)
Gen3 parts had ≤24 ports, so one dword/VS (`[23:0]`) sufficed and 0xe0–0xe7
cleanly held VS0–VS7. **Atlas has 98/128 ports and its port bitmaps are 4 dwords
(128-bit)** — proven by the clock bitmap read across 0x30C/0x310/0x314/0x318 with
`maxPorts=128` (`PlxApiDirect.c:2373`). Two possibilities, **not disambiguated
from public sources**:
- **(A)** VS0's vector widened to 4 dwords (0xe0–0xe3 = one 128-bit VS0 bitmap) →
  legacy per-VS stride is broken, VS1–3 vectors live elsewhere / only exist in
  fabric mode. **This matches the observation of "a VS0 vector but no VS1–3
  vectors."**
- **(B)** still four single-dword per-VS vectors (VS0..VS3 = 0xe0..0xe3), each
  addressing only ports 0–31 — a real limitation on a 98-port part.

Tie-breaker toward **(A)**: on Atlas the SDK's *classic* multi-host path
(`PlxMH_GetProperties`) returns `PLX_STATUS_UNSUPPORTED` — it supports only
Cygnus/Draco/Capella (`ApiFunc.c:3006`). Atlas does genuine multi-host via
**Fabric mode** (Q4), implying 0xe0–0xe3 is the base-switch partition bitmap and
≥2-host separation is done via fabric/CCR, not four legacy per-VS dwords.
**Recommended empirical test:** write one bit to 0xe4 (0x390) and see whether it
reads back as a VS1 member or is ignored.

### VS1–3 Upstream encoding — SAME structured layout as VS0
**Confirmed identical.** The SDK reads *every* VS upstream register with one
decode via `0x360 + i·4` (`ApiFunc.c:3068`, `I2cAaUsb.c:1834`); the "plain 32-bit
field" description for VS1–3 is just docs shorthand. Fields, reconciled with your
Atlas findings:
- **Upstream port:** Gen3 `[4:0]` (mask 0x1F); **Atlas widened to `[7:0]`** —
  proven: `(regVal>>0)&0xFF` at `PlxApiDirect.c:2570`. Matches your "[7:0]".
- **NT (NT0) enable bit 13**, NT port `[12:8]`; **NT2 (NT1) enable bit 21**, NT2
  port `[20:16]` (Gen3 decode `pex-status.c:168,170`).
- **DMA mode 24, VC mode 25, ALUT enables 30/31** — Atlas-era additions in the
  upper bits the Gen3 layout leaves free (no conflict); exact positions confirmed
  only by your RE work.
Any per-VS upstream write must preserve this structure, not treat it as an opaque
u32. Sources: `github.com/DaiZhiyuan/PlxSdk`, `github.com/xiallc/broadcom_pci_pcie_sdk`,
`github.com/benmcollins/pex87xx`.

---

## Q3 — "Atlas mode" (dword 3 [17:16]) and STRAP_FANOUT_EN (bit 20)

**Numeric 2-bit "Atlas mode" encoding: UNKNOWN.** But the mode *set* it selects
among, and the fan-out↔synthetic split, are well established.

### The modes (from Broadcom BC-0484EN)
- **Base / "Base with MPT" mode = NVMe fan-out** ("programmed to provide NVMe
  fanout … with MPT endpoint").
- **Synthetic mode** ("synthesize the hierarchy from the host point of view …
  done with the embedded CPU"). Embedded **ARM Cortex-R4** drives it.
- **Multi-host / NT 2.0** (up to 48 NT ports) — a capability layered on the
  above, not a mutually exclusive strap.
(https://docs.broadcom.com/doc/BC-0484EN)

### Fan-out vs Synthetic is a real, SBR-vs-FW boot split (strongest evidence)
The Serial Cables Atlas cards (exact PEX88096 B0, `1000:c010`) expose it directly:
- Heartbeat LED: **solid = base fan-out mode**, **blinking = synthetic mode**.
- Flash payload per mode: **`fdl sbr` = write SBR "(Applicable in base switch
  mode)" / "for fan-out switch mode"**; **`fdl fw` = program FW "(Applicable in
  Synthetic mode)."** Gen4 usage is `fdl cfg|sbr|fw|mfg`.
- The Gen4 product page ships **two separate images**: normal firmware *and* a
  distinct **"Base Mode Firmware (ZIP)."**
Sources: Serial Cables *Atlas2 MCIO Host Adapter Card User's Manual* REV1.0
(https://www.serialcables.com/wp-content/uploads/2023/05/ATLAS2-GEN5-MCIO-Host-Adapter-Card_Users-Manual_V10.pdf);
*PCI-AD-x16HE-BG4* REV1.4
(https://www.serialcables.com/wp-content/uploads/2020/11/PCI-AD-x16HE-BG4-users-manual_REV1.4-1.pdf);
product page id138
(https://serialcables.com/product/pcie-gen4/serial-cables-pcie-gen4-x16-sff-8644-host-card-with-broadcom-atlas-b0-pcie-switch-skupci4-ad-x16he-bg4-id138);
ManualsLib PCI4-AD-x16HI-BG4
(https://www.manualslib.com/manual/2485527/Serial-Cables-Pci4-Ad-X16hi-Bg4.html).

### Inference on the strap interaction (partly UNKNOWN)
- **STRAP_FANOUT_EN (bit 20)** ≈ "boot as plain SBR-driven fan-out (base) switch;
  consume the SBR per-port config directly, don't await synthetic FW." Consistent
  with every reference image being a fully-populated fan-out SBR.
- **Atlas mode [17:16]** = top-level personality selector, most plausibly
  `{base/fan-out, synthetic, NT/multi-host, reserved}`; all reference images read
  0 → strongest inference `0 = base/fan-out`. **Which value = which mode is
  UNKNOWN.** Whether Atlas-mode and STRAP_FANOUT_EN are redundant, hierarchical,
  or orthogonal is **UNKNOWN**.
- This also cross-checks CCR `0xB0[1:0]` (Q4): `0 = Standard/base`, `1 = Fabric` —
  so at runtime the base-vs-fabric personality is a live CCR bit; the SBR
  Atlas-mode/STRAP_FANOUT_EN fields are the persisted form.

---

## Q4 — Multi-host bring-up sequence on Atlas

### Two distinct multi-host models — select via CCR `0xB0[1:0]`
`ATLAS_REG_CCR_PCIE_SW_MODE = _REG_CCR(0xB0)` (`PlxApiDirect.h:101`, decode
`PlxApiDirect.c:2550`):
- **`0b00` Standard / Base-Switch (BSW)** — single upstream from
  `ATLAS_REG_VS0_UPSTREAM 0x360[7:0]`; this is your fan-out start state. Can be
  *partitioned* into virtual switches with the legacy VS block (Q2).
- **`0b01` Fabric / Smart-Switch (SSW = ExpressFabric)** — full multi-host.
  Management port from **CCR `0x170[15:8]`** (`ATLAS_REG_CCR_PCIE_CONFIG`,
  `PlxApiDirect.c:2576`); every non-mgmt upstream becomes a host port
  (`PlxApiDirect.c:2673`).

Two register windows: VS/port CSRs at **AXI `0x6080_0000` = BAR0 + 0x800000**
(matches your base), chip-config **CCR at AXI `0xFFF0_0000`**, reached via the
index/AXI access regs `ATLAS_REG_IDX_AXI_ADDR 0x1F0100` / `_DATA 0x1F0104` /
`_CTRL 0x1F0108` (CTRL bits WRITE=1<<0, READ=1<<1, BUSY=1<<2, READ_VALID=1<<3).

### Per-port role in Fabric mode
CCR **`PORT_TYPE` at `0x120 + station·4`, 2 bits/port, `0b01` = Fabric port**
(`PlxApiDirect.c:2694`). In fabric mode the embedded ARM fabric-manager binds
host/fabric ports dynamically (no static per-VS downstream bitmap). This is the
"ExpressFabric" model in BC-0484EN (I/O sharing, ≤48 NT, ≤48 DMA, TWC host-to-host).

### Recommended bring-up order (base-switch / virtual-switch partitioning)
Proven by the SDK write sequence:
1. Operate from the **management port** — Mgmt Port Config 0xd5/0x354
   (active-enable bit 5, active port `[4:0]`; redundant-enable bit 13, port
   `[12:8]`; `ApiFunc.c:3039`).
2. Program each VS **Upstream** (0xd8–0xdb / 0x360+i·4): upstream port `[7:0]`,
   + NT/NT2/DMA/VC/ALUT fields.
3. Program each VS **Downstream Port Vector** (0xe0–0xe3 / 0x380+i·4).
4. Set the VS bit in **VS Enable** (0xd6 / 0x358).
5. **Reset the VS** to apply membership: VS Reset **0x3A0 (dword 0xe8)** — set
   the VS's bit, wait ~10 ms, clear (`ApiFunc.c:3229`).

### "Config Release / Initiate Configuration" (0xeb / 0x3AC bit 0) — UNKNOWN, inferred
This register is **not present in the public SDK** (which predates Atlas fabric
bring-up and applies port-vector writes immediately, using only the 0x3A0 VS-reset
pulse). By analogy + the Chip-Bring-up-Control (0xd3) companion, 0xeb bit 0 is
the **commit/latch**: stage VS Enable + VS Upstream + port vectors → write 0xeb.0
"Initiate Configuration" → the switch/mgmt-CPU atomically applies the topology and
releases ports for enumeration (superset of the legacy 0x3A0 pulse). Confirm bit
semantics empirically (self-clearing? busy/done?); Broadcom reuses a
BUSY/READ_VALID handshake elsewhere (`PlxApiDirect.h:118`).

### Clocking for multi-host (board-level)
- Per-port **clock-enable** bitmap: 0x30C(0–31)/0x310(32–63)/0x314(64–95)/
  0x318(96–127), `maxPorts=128`; ports 116/117 report in bit positions 96/97
  (`PlxApiDirect.c:2396`). These are enables, not architecture selects.
- **Clock architecture:** each independent host arrives on its own reference
  domain, so host-/cable-facing ports must run **SRIS** (tolerates each side's
  independent SSC) or **SRNS** (SSC off end-to-end); local board endpoints can
  stay common-clock. Retimer/host-card links must match on both ends. The exact
  Atlas CSR/strap that sets per-port SRIS/SRNS/common is **UNKNOWN** publicly
  (set via SBR Clocking field + PCIe LinkControl2). Refs: BC-0484EN, PEX88T32-PB.

Sources: `github.com/DaiZhiyuan/PlxSdk`, `github.com/xiallc/broadcom_pci_pcie_sdk`
(`PlxApiDirect.c/.h`, `I2cAaUsb.c`, `ApiFunc.c`), `github.com/benmcollins/pex87xx`,
PEX8733/8734 datasheet (https://docs.broadcom.com/docs/12351852) ("a virtual
switch is created for each host port"), pci.ids 1000:c010
(https://admin.pci-ids.ucw.cz/read/PC/1000/c010).

---

## Q5 — NT (non-transparent) configuration on Atlas

### Driver support — the headline: NONE for Atlas, anywhere public
- **Mainline Linux has no PLX/Broadcom NTB driver at all.** `drivers/ntb/hw/` is
  `amd/ epf/ idt/ intel/ mscc/` — no `plx/`, no Kconfig entry (`gh api
  repos/torvalds/linux/contents/drivers/ntb/hw`). `mscc` = Microsemi switchtec,
  not Broadcom.
- `ntb_hw_plx` on Linux was only an **unmerged RFC** (Jeff Kirsher / iXsystems,
  87xx target — https://groups.google.com/g/linux-ntb/c/kO6IAj4dB5k), never
  mainlined.
- **The only shipping `ntb_hw_plx` is FreeBSD's** (Alexander Motin). It matches
  **only vendor `0x10b5`** IDs `0x87a0/0x87a1` (NT0/NT1 Link), `0x87b0/0x87b1`
  (NT0/NT1 Virtual) — ExpressLane/Capella-era. **Atlas is `1000:c010` (vendor
  `0x1000`), so this driver never binds a PEX88000.**
  (https://cgit.freebsd.org/src/plain/sys/dev/ntb/ntb_hw/ntb_hw_plx.c, L153–163).
- **`switchtec` does NOT cover Atlas** — verified by reading mainline
  `drivers/pci/switch/switchtec.c`: table is only `0x11f8` (Microsemi) + `0x1fff`
  (EFAR). Disregard every "Atlas uses switchtec" blog.

### PlxSdk and Atlas
The community fork `github.com/DaiZhiyuan/PlxSdk` (sibling `d4ddi0/PlxSdx`) is the
real Broadcom/Avago/PLX SDK with Atlas patches:
- `Include/PlxTypes.h:323` → `PLX_FAMILY_ATLAS` = chip codes **C010, C011, C012**.
- **Its NT drivers do NOT cover Atlas.** `Driver/Source.Plx8000_NT/PlxChipFn.c`
  switches only on `0x2300…0x9700` (Mira→Capella); no `0xC010` case anywhere in
  the NT drivers.
- Atlas is handled only by the **management driver** `Source.PlxSvc` + userspace
  `PlxApi/PlxApiDirect.c`, which **detects mode** (CCR `0xB0[1:0]`) but exposes
  **no NT/ALUT programming path**. The enum has `PLX_CHIP_MODE_STD_LEGACY_NT` /
  `..._STD_NT_DS_P2P` (`PlxTypes.h:333`) but the Atlas path never sets them.
- pci.ids: `1000:c010` = "PEX880xx PCIe Gen4 Switch"; subsystems include
  `100b` (Virtual Up/Downstream Port), and shared NT/DMA naming `2004` (Virtual
  PCIe TWC/NT 2.0 Endpoint), `2005` (Virtual PCIe gDMA Endpoint).

### NT-Virtual vs NT-Link, A-LUT, BAR windows (from the 87xx analog)
Atlas NT register semantics are NDA; FreeBSD's 87xx driver + SDK legacy decode
are the authoritative public analog:
- **Role split:** an NT bridge = two back-to-back endpoints. **NT-Link** faces the
  far host/domain, **NT-Virtual** faces the local host. `PlxCm/MonCmds.c` decode:
  port `[15:10]=11_1xxxb` → NT ports, **bit0=0 → Link, bit0=1 → Virtual**, bit1
  selects NT0/NT1. FreeBSD: `PLX_NT0_BASE=0x3E000`, `PLX_NT1_BASE=0x3C000`,
  `PLX_NTX_LINK_OFFSET=0x1000` (Virtual and Link blocks 0x1000 apart).
- **A-LUT (Address Lookup Table):** FreeBSD `PLX_MAX_SPLIT=128`; A-LUT enable is a
  **per-NT-instance bit** — `alut = (val==0x3)?1 : ((val&(1<<ntx))?2:0)`,
  entries `= 128*alut`. Value `0x3` enables both — exactly the shape of your SBR
  **ALUT NT enable bit30 / ALUT NT2 enable bit31**. With A-LUT on, BAR2 splits
  into ≤128 windows indexed by the requester's bus/slot (function passed through).
- **B2B / NTB-to-NTB BAR setup** (`ntb_setup_peer`): set peer BAR0/1 size+addr,
  program Virtual→Link translation, enable Link LUT entries for the peer, enable
  Virtual LUT entry 0 for `0:0.*` to bootstrap. 8 scratchpads (+4 pattern),
  16 doorbells.
- Both the FreeBSD man page and the RFC note basic NT config (enable NT one/both
  sides, NTB-to-NTB vs NTB-to-RP, BAR sizes) is done by **serial EEPROM / I²C at
  reset**, not by the OS driver — i.e. it belongs in the SBR (see Q6).

**Bottom line:** no open or reference driver programs Atlas NT. An Atlas NT
driver, if it exists, is in Broadcom's NDA SDK — **UNKNOWN/not public**. Reconcile
of SDK VS0-upstream `0x360` vs your RE'd `0xd8` (both name the same VS0 register)
is **UNKNOWN** from public source.

---

## Q6 — Persistence: baking VS/NT/multi-host into the SBR

**Yes — persistence with zero host software is the intended design.** The switch
loads port config, VS assignment and mgmt-CPU firmware from the serial boot ROM at
reset. But the *public* SDK treats the Atlas SBR as an opaque blob.

- **The vendor flow is: build an SBR → flash it at 0x400 → boot standalone.** The
  PlxSdk tool operates on it as raw binary at exactly offset 0x400
  (`PlxCm/MonCmds.c` spiload/spisave help ~L5525):
  ```
  spiload C:\MySbr.bin /o 400
  spisave C:\MySbr.bin /o 400 /s 1000 /mmr
  ```
  Its own examples name the file `MySbr.bin` and default to `/o 400`.
- **The public SDK cannot parse or generate the Atlas SBR.** The `eep` decoder
  has per-family record decoders for Bridge/Mira/Cygnus/Draco/Capella-1, but
  **`PLX_FAMILY_CAPELLA_2` and `PLX_FAMILY_ATLAS` fall through to "UNKNOWN"**
  (`MonCmds.c` ~L4389). The legacy EEPROM signature it knows is **`0x1516`**
  (`RegDefs.c:618`) — not the Atlas SBR signature `0xc0103dc4`. So the Atlas SBR
  container (22-dword index, 104-dword SoC region, PSB/PSB-SerDes/CCR write-record
  blocks, your checksum) is a **distinct newer format the public tool does not
  build/validate.**
- **The SBR block taxonomy is corroborated as real Atlas AXI regions**
  (`PlxApi/MdioSpliceUsb.c` ~L125): PSB-Fusion `0x60000000`, PSB-Core `0x60001000`,
  PSB-Generic `0x60004C00`, PSB-DCR `0x60008000`, PSB-PEX/GEP `0x60800000`,
  PSW0..5 SerDes `0x70000000` (16 lanes each), CCR `0xFFF00000`. So SBR "PSB
  register-write records" → 0x6000_0000 space, "PSB-SerDes / PSW lane blocks" →
  0x7000_0000 SerDes space, "CCR register update programs" (dwords 7–24/41–49) →
  0xFFF0_0000 CCR block. **The SBR is a scripted list of AXI register writes
  replayed by the mgmt CPU at boot** — which is exactly why a full multi-host /
  VS / NT / port-type config can be made persistent with no host driver.
- **The high-level-config → register-write-record generator is Broadcom's closed
  PDE / SBR-builder** (alluded to in BC-0484EN "GUI interfaces … to aid in
  configuring"). Field reports confirm the tool as **PEXDeviceEditor (PDE)** but
  with its flash editor greyed out on secure parts (Q8). Whether PDE compiles a
  high-level fabric/VS/NT description into those records is the **vendor-intended
  flow but the algorithm is not in any public source — UNKNOWN/NDA. This is
  precisely the gap `pexctl` fills.**

Sources: `github.com/DaiZhiyuan/PlxSdk`, `github.com/d4ddi0/PlxSdx`, FreeBSD
`ntb_hw_plx.c`, https://admin.pci-ids.ucw.cz/read/PC/1000/c010, BC-0484EN.

---

## Q7 — Locating the documentation

### Publicly reachable (no login, confirmed downloadable)
- **BC-0484EN — PEX88000 Series Product Brief** — canonical marketing brief;
  confirms embedded **ARM mCPU**, ExpressFabric, 48 DMA channels, two mgmt ports,
  ordering table (SS02-0B00-00 = PEX88096B0-DB 98-lane; **-02 = Secure Boot**),
  RDK block diagram, VisionPAK SerDes eye tooling. **No register/I²C/SBR detail.**
  https://docs.broadcom.com/doc/BC-0484EN (mirror:
  https://www.mouser.com/datasheet/2/678/BC_0484EN_2019_07_17-3498215.pdf).
- **BC00-0445EN — "PCI Express Switches for Data Center and Cloud Platforms"** —
  selection tables (lanes/ports/latency/power). https://docs.broadcom.com/doc/BC00-0445EN
- **PEX89000_PB102** — Gen5 sibling (Capella) product brief.
  https://www.mouser.com/datasheet/2/678/PEX89000_PB102-3394994.pdf
- **Liqid × Broadcom PEX88000 Gen4 RDK flyer** — eval/RDK overview, MCPU debug
  ports. https://global-uploads.webflow.com/5ab1342d0735aa53115fca62/5ed93805f17e61334485d4e9_Liqid-Broadcom-RDK_060420.pdf

### Exists but NDA / Broadcom-login gated (indexed by KB 234074)
Broadcom KB **234074** (https://knowledge.broadcom.com/external/article/234074/)
names the real engineering docs by exact ID; none resolve to a public PDF:
- **`pex88000-rm109`** (and older `pex88000-rm108`) — **PEX88000 Register Manual**
  (the "RM109" the brief expected; defines 0xd0/0xd1 NVM, 0xd3 Chip Bring-up, the
  VS block). NDA.
- **`pex88000-pg114`** — PEX88000 Programming Guide. NDA.
- **`pex88000-89000-pcie-sdk-ug100`** — **SDK User Guide shared by Atlas AND
  Capella** (see Q10). NDA.
- **`pex89000-g5-serdes-ug100`** — Gen5 SerDes UG. NDA.
- **`pex880xx-sb-sign-an102`, `pex89xxx-sb-sign-an102/an100`** — Secure Boot
  image-signing app notes (why -02 parts reject arbitrary FW). NDA.

### Partial / unverified
- manualzz doc 60238941 ("PEX88000 … Specification") — **HTTP 403**, content
  unverified (likely a re-host of BC-0484EN). aichiplink SS02-0B00-02 "guide" —
  **403 / AI-generated, not primary.** Classic mirrors (alldatasheet,
  datasheetspdf, chipfind) have **no PEX88000/88096 entries** — these are OEM-only
  parts, never distributed broadly, so no aggregator/archive copy of RM109/UG100
  surfaced. **UNKNOWN whether any archive.org copy exists — none found.**

**Bottom line:** only briefs/selection guides/RDK flyer are public; every
register-level doc is NDA and correctly named in KB 234074.

---

## Q8 — Real-world field reports

### Level1Techs "Neverending Story" thread (canonical)
https://forum.level1techs.com/t/a-neverending-story-.../171428
- **User `itterative`** ran a **PEX88096** board with **"firmware mode set to
  5x16"**; board appears in `lspci` with correct topology **but no downstream
  devices visible** across several GPUs (AMD/NVIDIA/Intel) on a **B550M**.
  Resolution (post ~#1000): the board "**expected the adapter to have a PCIe
  insertion function**" (hot-plug/PRSNT signalling).
- **User `vitabis`**: bifurcation **Auto(x16) failed; `x8x8` made the switch +
  downstream devices appear**. Finished **P2P ("Poor(er) man's local AI")** using
  the PLX88096 board — **P2P worked on AM5, NOT AM4**. Concrete fixes: kernel
  **`pcie_aspm=off`** (clears AER errors); BIOS **AER `Auto`→`Supported`**. Board
  used **as-shipped, no register/EEPROM edits.** (post #1015)
- **DIP switches (`AllenLYTC3249`):** "only one should be in the 'Set' position,
  since they now require encrypted firmware to config since PEX880xx." Advised
  "grab the driver from Broadcom & apply patches." `westfox35` couldn't get a
  "big black switch" to matter.
- **Tooling:** **PEXDeviceEditor (PDE)** — "devices are greyed out, can't get to
  flash editor"; **PlxCm** referenced as maybe functional regardless of FW.
  Newer boards = **SPI flash, 1 image per valid DIP config**, accessed via mgmt
  link. **`SpiFileLoad` vs `EEpromFileLoad`** = Gen4+ vs Gen3 flash pathways.

### The one concrete EEPROM-edit report (Gen3, same VS/NT lineage)
https://forum.level1techs.com/t/pcie-switches-dma-vs-non-dma-and-nvme-pex8749-vs-48-47-24-etc/194853
- A user **"reprogrammed the EEPROM of my PEX8749 switches to set up lane counts."**
  Board: **DiLinker LRNV9349-8I** (PEX8749 8i NVMe). Byte table is inside a posted
  image (not extractable). Illustrative PlxMon-style syntax quoted:
  **`port 8 / offset 007c / val: 000000E1`** (per-port config at offset 0x7C).
  In-thread limit: **"PLXMon doesn't seem to be able to do it"** for some
  bifurcations — motivation for an open tool.

### Named Atlas (PEX88096) boards
- **Serial Cables PCI4-AD-x16HE-BG4** ("Atlas B0" host card): **DIP-switch
  bifurcation 1×16 / 2×8 / 4×4 / 8×2**; host + target mode; common clock,
  hot-plug, **SRNS & SRIS**; 4× SFF-8644; **firmware 4.3 (2021-03-23)**; ~$1,295;
  "only bifurcates down to the host BIOS minimum."
  https://serialcables.com/product/pcie-gen4/...id138 ,
  https://www.ebay.com/itm/285895223186
- **AIC J5010-02-G4** — Gen4 PCIe JBOX, Atlas PEX88096, 2× SFF-8644 uplink.
  https://www.aicipc.com/tw/productdetail/51313
- **C-Payne** — has a "Gen4 packet switch adapters" category but **no PEX88000
  board confirmed in stock**; **UNKNOWN** if one ever shipped. **LinkX** — no hit.

### Chinese boards / open hardware (richest open artifact)
- **OSHWHub project "PEX88096-PCIE4-Switch-GPU 底板套件" by `malong`** —
  https://oshwhub.com/malong/pex88096-pcie4-switch-gpu-basepl :
  - Retail Atlas parts all **rev B0**; **two packages only** —
    88096/88080/88064 share one (1.0 mm BGA), 88048/88032/88024 share another
    (0.8 mm); pin-compatible within each.
  - **You can firmware-limit channel count** (run a 88096 as an 88048) with "no
    real power difference" → **lane/port count is an SBR/FW setting, not fused.**
  - Chip exposes **I2C_SCL0–5 / I2C_SDA0–5 (five/six I²C sets)**; need 2K pull-ups
    to 1.8 V, level-shift to 3.3 V — the management/SBR-load bus.
- **Chiphell**: PEX88096 AIC unboxing thread "至多80盘NVME 5卡4090…" (Apr 2025,
  https://chiphell.com/forum.php?mod=viewthread&tid=2685098) — anti-bot blocked,
  post bodies not extractable. **UNKNOWN** config specifics.
- **Firmware bounty (demand signal):** a user offered **€100 for any PEX88096
  firmware image, any vendor** (https://x.com/nb4ld/status/2061707393445122063) —
  underscores how gated Atlas FW/SBR is.
- **Distrust list (AI-generated, cite with caution):** aichiplink, sugermint,
  aliexpress "wiki-ssr" — all repeat the **false** "configurable via Switchtec
  firmware" claim. Do not propagate.

**Honest limit:** no public forum/GitHub source independently corroborates your
RE'd runtime offsets (0xd6/0xd8/0xe0–0xe3/0xeb) or the SBR sig `0xc0103dc4` @
0x400 — as far as the public record goes, **your reverse-engineering is novel.**

---

## Q9 — Management / out-of-band interfaces & flash recovery

Primary source: **Serial Cables Atlas2 MCIO Host Adapter Card User's Manual
REV1.0 (May 2023)** (Gen5 card, identical mgmt scheme to the Gen4 Atlas card).

### I²C / SMBus
- The switch exposes a **2-wire mgmt bus on `ATLAS_SCL` / `ATLAS_SDA`** (MCIO pins
  **A11/A12**), present in all side-band modes (always available). Distinct from
  the per-port downstream SMBus (`I2C_SCL0..3/SDA0..3` reaching the drives).
- On the card the **on-board MCU is the SMBus master**; the host doesn't touch it.
  Downstream drive SMBus via `iicwr`/`iicw` (example drive slave `0xd4`).
- **The Atlas switch's OWN SMBus slave address is UNKNOWN** — not in the Serial
  Cables manual; it lives in the NDA RM109 / hardware design manual. OSHWHub
  confirms 5–6 I²C sets on the chip (Q8).
- `bist` = on-board I²C device diagnostic.

### CSR + flash access via the MCU (the OOB path)
- `mw <reg(H)> <data(H)>` — write a 32-bit CSR (full range).
- `dr <reg(H)> [count]` — dump CSRs (example base `0x60800000` = the PEX/GEP AXI
  base, matching PlxSdk).
- `dp <port(D)>` — dump per-port registers.
- **`df <addr(H)> [count]` — dump Atlas SPI flash**; the manual's worked example
  reads **`0x00000400`** — exactly the SBR offset. So **`df 0x400` reads the SBR
  over serial with no host PCIe.**
- **`fdl sbr|fw|mfg|mcu`** — write flash: `sbr` = SBR (base mode), `fw` = FW
  (synthetic), `mfg` = mfg block, `mcu` = card MCU. Gen4 syntax `fdl cfg|sbr|fw|mfg`.

### UART / serial consoles
- **Card MCU console:** Type-C USB (`CN6`), USB-CDC virtual COM
  (`VID_03EB&PID_2018` = Atmel/Microchip SAM/AVR MCU), **115200 8N1, no flow
  control** — where `fdl/df/dr/mw` run.
- **`J1` = "Atlas2 switch SDB port," UART 3.3V TTL** — Broadcom **Serial Debug Bus**
  into the switch.
- **`J2` = "Atlas2 switch UART port," UART 3.3V TTL** — switch-FW console (needs FW
  support).
- **`J6` ON = "MCU without SDB of switch control"** — tri-states the MCU off the
  SDB so an **external SDB debugger drives the switch** (key when the MCU path is
  dead).

### Card-level MCU recovery straps
- **`J7` ON = force MCU into FW-upgrade (bootloader) mode** → USB mass-storage,
  drop `.srec`/`update.txt`. Gen4 equivalent = **CN15/CN14** headers.
- These recover the **card MCU**, not the Atlas flash. **No documented Serial
  Cables strap forces the Atlas chip itself into a safe/skip-SBR boot** — that is
  the CSR you already have (**0xd3 "disable SBR load on lvl1" bit 3**). **UNKNOWN**
  whether a physical Atlas boot-strap pin exposes the same function pre-boot.

### JTAG / MDIO / mgmt CPU
- **JTAG: UNKNOWN** (no header documented; debug path is SDB, not JTAG).
- **MDIO: UNKNOWN / N/A.** Note PlxSdk has an `MdioSpliceUsb.c` (MDIO-over-USB
  splice for SerDes/AXI access) — an MDIO-style path into the AXI space may exist,
  but no board exposes it.
- **Embedded ARM mCPU** confirmed (BC-0484EN), two dedicated mgmt ports, "MCPU
  debug" 1-lane connectors on the RDK.
- **switchtec claim = false** (verified against mainline source); Atlas is managed
  by the Broadcom/PLX SDK + the on-card MCU CLI, not switchtec.

### Recommended bad-SBR recovery order
1. **`fdl sbr`** over the 115200 USB-CDC MCU console (works while MCU + Atlas
   alive); 2. verify with **`df 0x400`**; 3. if the MCU can't reach the switch,
   **`J6` ON** to free the **SDB** bus and drive it with an external SDB debugger;
   4. last resort, clip an **external SPI programmer (CH341A/flashrom)** onto the
   NOR flash (part number not named — UNKNOWN). On **-02 Secure Boot** parts a raw
   external rewrite of a signed FW region fails verification; the **unsigned SBR @
   0x400 is the safely-rewritable piece.** The runtime NVM CSRs (0xd0/0xd1) and
   0xd3 bit 3 are the same flash engine these CLI commands wrap.

Sources: Serial Cables Atlas2 manual (proId=75,
https://serialcables.com/vendor-media/extra/upload/media/studio_672b8ffaee0fc2044331730911754.pdf);
Gen4 Atlas card ManualsLib
(https://www.manualslib.com/manual/2485527/Serial-Cables-Pci4-Ad-X16hi-Bg4.html);
BC-0484EN.

---

## Q10 — Cross-family transferability (Atlas ↔ Capella / older PLX)

### Strongest finding: Atlas and Capella share ONE SDK user guide
Broadcom KB 234074 lists **`pex88000-89000-pcie-sdk-ug100`** — the **PCIe SDK User
Guide shared by BOTH PEX88000 (Atlas, Gen4) and PEX89000 (Capella, Gen5).**
Broadcom treats the two generations as **one software/config model**: same mgmt
API, SBR/EEPROM authoring flow, VS/NT/DMA object model, plxmon-style tooling.
→ **Model transfer Atlas↔Capella: HIGH.** Expect differences only in lane/port
counts, SerDes, and register base offsets — not in the object model.

### Is Capella more public? No — equally NDA at register level
Public artifacts for each are only product briefs (Capella PB:
https://docs.broadcom.com/docs/PEX89000-Managed-PCI-Express-5.0-Switches ,
https://www.mouser.com/datasheet/2/678/PEX89000_PB102-3394994.pdf ; Atlas
BC-0484EN). No public Capella doc gives VS port-vector / upstream / NT offsets.
The only public Capella VS/NT description is secondary/AI (Grokipedia PEX89144 —
non-authoritative; names no offsets).

### PCI-ID structure is identical → same VS/NT/gDMA decomposition
Capella mirrors Atlas 1:1: Virtual Up/Downstream Port (`100b`), **Virtual PCIe
TWC/NT 2.0 Endpoint (`2004`)**, **Virtual PCIe gDMA Endpoint (`2005`)** — same
device-ID scheme (pciutils master pci.ids). "TWC/NT 2.0" and "gDMA" naming is
common to both → the NT (Tunneled Window Connection / NT 2.0) and host-to-host
global-DMA models are shared.

### Best older PUBLIC register-model reference: PEX9700 "ExpressFabric" (Gen3)
Atlas's direct ancestor is **not** the transparent PEX87xx switches — it's the
**PLX/Avago PEX9700 ExpressFabric** series (first Gen3 managed multi-host fabric).
The "virtual switch + NT + host-to-host DMA + fabric-management-CPU + any-port-as-
host + DPC" model your registers implement comes from this lineage.
- PEX9700 PB: https://www.mouser.com/datasheet/2/678/PLX_PEX9700_ExpressFabric_PB_AV00_0327EN_051618-2301526.pdf
- SemiAccurate deep-dive (best public architecture writeup, 2015-05-12):
  https://semiaccurate.com/2015/05/12/avagos-pex9700-turns-plx-pcie3-switch-fabric/
  — "any port can be a host port or downstream port" (= VS upstream + port
  vector); I/O sharing "looks like SR-IOV to each host"; "management processor …
  emulates whatever device the server is supposed to see" (= synthetic mode);
  "tunnel, DMA, and share devices" host-to-host (= gDMA/TWC-NT); DPC.
- **PEX8749/8733** (Gen3 ExpressLane) = the smaller register ancestor for the
  **NT + DMA + multi-host-upstream** primitives ("two NT ports, four DMA engines,
  two VCs," "Multi-Host mode … up to six host/upstream ports"). Public detail
  only in the **errata** (https://docs.broadcom.com/doc/PEX8749-48-47-33-32-25-24-23-17-16-13-12-Errata-and-Cautions)
  and product briefs; no byte-level VS registers.

### For `pexctl`
- Anchor the *architecture* on PEX9700 ExpressFabric + PEX8749/33 primitives.
- Anchor the *runtime register offsets* on the PlxSdk Atlas map (Q2/Q4).
- The byte-level VS/SBR truth (0xd6/0xd8/0xe0–0xe3/0xeb, SBR@0x400/`0xc0103dc4`)
  is defined only in NDA `pex88000-rm109` / `pex88000-pg114` — publicly **novel**
  to your RE. A Capella port of `pexctl` should be low-effort given the shared
  SDK UG.

---

## SURPRISES / LEADS

1. **CCR is the Rosetta Stone.** The public PlxSdk hands over the Atlas AXI map
   (PSB `0x6000_0000`, PSW-SerDes `0x7000_0000`, PEX/GEP `0x6080_0000`, CCR
   `0xFFF0_0000`) and concrete CCR registers: **mode `0xB0[1:0]`** (0=base,
   1=fabric), **port-type `0x120`** (2 bits/port, 01=fabric), **PCIe-config
   `0x170[15:8]`** (fabric mgmt port), **VS0-upstream `0x360`**. Cross-referencing
   these against your SBR SoC dwords (esp. Port Type dwords 25–32 ↔ CCR 0x120,
   and CCR-update programs in dwords 7–24/41–49 ↔ the `0xFFF0_0000` block) is the
   most promising way to decode the remaining enums without NDA docs.

2. **The SBR is a replayed AXI write-script.** PSB/PSB-SerDes/PSW/CCR write-record
   blocks map 1:1 onto the AXI regions above; the mgmt CPU replays them at boot.
   That means `pexctl` can, in principle, express *any* multi-host/VS/NT config as
   a set of AXI writes baked into those records — no host driver, no NDA generator.

3. **Two multi-host models, not one.** Base-Switch partitioning (legacy VS block,
   0xd6/0xd8/0xe0) vs Fabric/SSW (embedded fabric-manager, dynamic binding),
   selected by CCR `0xB0[1:0]`. Your VS registers are the *base-switch* path; true
   ExpressFabric multi-host may need fabric mode + the ARM manager. **Test which
   your board's SBR selects before assuming the VS-vector path scales to 98 ports.**

4. **The VS0-vector width is the one open silicon question** (128-bit VS0 vs four
   per-VS single-dword vectors). Cheap experiment: write a bit to **0xe4 (0x390)**
   and read back — decides model (A) vs (B) in Q2.

5. **`fdl sbr` + `df 0x400` over the 115200 MCU console is your un-brick button** —
   works without host enumeration, and the SBR (unsigned) is rewritable even on
   Secure-Boot -02 parts. `J6` ON → external SDB debugger is the fallback if the
   MCU can't reach the switch.

---

### 5-line summary of the most important findings
1. **No mainline driver manages Atlas** — I verified `switchtec.c` binds only
   Microsemi/EFAR, and `ntb_hw_plx` (FreeBSD only) matches `0x10b5` 87xx, never
   `1000:c010`; the "Atlas uses switchtec" blogs are wrong.
2. **The public `PlxSdk` fork leaks the Atlas register map** — `PLX_FAMILY_ATLAS`
   (C010/C011/C012), AXI bases, CCR mode `0xB0[1:0]` (0=base/1=fabric), per-port
   Port-Type CCR `0x120`, VS0-upstream `0x360`, `spiload/spisave … /o 400`.
3. **The exact SBR Port-Type / Clocking / Atlas-mode 2-bit enums remain NDA
   (rm109/pg114)**, but Port-Type almost certainly persists CCR `0x120` (01=fabric)
   and the fan-out↔synthetic split is real (`fdl sbr` vs `fdl fw`, LED heartbeat).
4. **VS1–3 use VS0's structured Upstream layout and per-VS port vectors
   (0x380+i·4), applied via VS Reset 0x3A0** — but whether VS0's vector is 128-bit
   (Atlas) or four per-VS dwords is the one open silicon test (write to 0xe4).
5. **Out-of-band recovery is documented and works** — the Serial Cables MCU CLI
   does `df 0x400` / `fdl sbr` over 115200 8N1 USB-CDC, with an SDB-debugger
   fallback (`J6`), and the unsigned SBR is rewritable even on Secure-Boot parts.
