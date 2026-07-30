# PEX88096 research report (Grok agent)

**Scope:** NEW citable findings for open questions Q1–Q10 on Broadcom/PLX
**PEX88096** (Atlas, PEX88000 Gen4, PCI ID `1000:c010`, rev B0).  
**Method:** public product briefs, Serial Cables OEM manuals, FreeBSD/Linux
NTB sources, Level1Techs / ServeTheHome field reports, secondaryOh, I see. You wanted **new, citable** answers on the PEX88096 open questions — not another walk through the SBR you already mapped. I dug public briefs, Serial Cables OEM manuals, FreeBSD NTB sources, and field threads, and wrote the full report to:

**`research/grok.md`**

### What moved the needle

| Area | Result |
|------|--------|
| **Q1 enums** | Exact 0–3 tables still **UNKNOWN**. Strong lead: Serial Cables modes use **I = SRIS / N = SRNS**, and images like `B0 HOST_X4_SRIS_V02.bin` — best path is SBR byte-diff of I vs N images. |
| **Q2 VS1–3** | Port-vector registers for VS1–3 still **not found**. Gen2/Gen3 briefs confirm the isolated virtual-switch model; Atlas Synthetic mode likely owns complex membership. |
| **Q3 Atlas mode / FANOUT** | Bit encodings **UNKNOWN**, but BC-0484EN names **Base / Base+MPT / Synthetic**; Serial Cables maps **SBR → Base**, **FW → Synthetic**. |
| **Q5 NTB drivers** | FreeBSD `ntb_hw_plx` is Gen3-only (`10b5:87a*/87b*`, ALUT, Link vs Virtual). **No Atlas mainline/out-of-tree NTB driver** found. MPT mgmt DID **`1000:00b2`**. |
| **Q7 manuals** | **Only product briefs** public. RM109/UG100/datasheet/errata: **no public mirror**. |
| **Q8/Q9** | Best field gold is the [SerialCables STH thread](https://forums.servethehome.com/index.php?threads/help-with-serialcables-com-pci4-ad-x16he-bg4.47497/): USB CLI, `fdl sbr`/`fdl fw`, SBR-disable jumper, Atlas UART + `ATLAS_SCL/SDA`. Multi-host with register dumps: **still empty**. |
| **Q10 Capella** | Base/Synthetic + SRIS/SRNS transfer well; CSR map unproven. Atlas2 heartbeat LED: solid = Base, blink = Synthetic. |

### Highest-ROI next lead

Get Serial Cables (or other OEM) **SRIS vs SRNS** SBR binaries of the same bifurcation and diff SoC dwords 33–39. That is the open path to Clocking-mode enums without NDA.
 means support SRNS”*.  
   Cold power-cycle required after `setmode` writes config into Atlas.
   - Source: Serial Cables *PCI-AD-x16HE-BG4 User’s Guide* (PDF from
     [serialcables.com product media](https://serialcables.com/product/pcie-gen4/serial-cables-pcie-gen4-x16-sff-8644-host-card-with-broadcom-atlas-b0-pcie-switch-skupci4-ad-x16he-bg4-id138))

3. **Field reports name SBR/config images after SRIS**, e.g.
   `B0 HOST_X4_SRIS_V02.bin` flashed with `fdl sbr` on Serial Cables cards
   (STH thread). That strongly implies SBR-level clocking selection for
   base mode, consistent with a per-port Clocking-mode table — **but does
   not prove the 2-bit codes 0/1/2/3**.
   - Source: [ServeTheHome: SerialCables PCI4-AD-x16HE-BG4](https://forums.servethehome.com/index.php?threads/help-with-serialcables-com-pci4-ad-x16he-bg4.47497/)

4. **All-zero in live fan-out boards remains the only empirical anchor.**
   Product boards and Base RDK images run with Port Type = 0 and Clocking
   mode = 0 while upstream is selected solely via `STRAP_UPSTRM_PORT` and
   stations are x16. Therefore **value 0 is the production default for
   transparent fan-out**, almost certainly “common-clock / default role”
   rather than “disabled.” **Values 1–3 remain UNKNOWN.**

### Hypotheses (explicitly unconfirmed)

| Field | Value | Plausible meaning (NOT confirmed) |
|-------|------:|-----------------------------------|
| Clocking mode | 0 | Common clock (CC) / default |
| Clocking mode | 1 | SRNS |
| Clocking mode | 2 | SRIS |
| Clocking mode | 3 | Reserved / constant-CLK / other |
| Port Type | 0 | Downstream transparent / auto (default) |
| Port Type | 1 | Upstream (or reserved; USP is also strapped) |
| Port Type | 2–3 | NT-virtual / NT-link (classic PLX NT roles) |

Port Type 1–3 mapping is **especially weak**: Gen3 PLX multi-host product
briefs describe virtual switches and NT ports, but never publish the
2-bit SBR codes used on Atlas. Do **not** program Port Type/Clocking
based on this table.

**Citations:** BC-0484EN; PEX89000-PB102; Serial Cables PCI-AD-x16HE-BG4
manual; STH SerialCables thread.

---

## Q2. Virtual-switch (multi-host) programming model; VS1–VS3 membership; VS1/2/3 Upstream encoding

### Findings

1. **Architectural model (public, family-level).** PEX88000 marketing
   states: any port can be a host or downstream port; up to **48 NTB
   ports** on the 96-lane device; multi-host topologies for hyper-scale /
   I/O sharing; complex multi-host multi-switch setups need **external
   management processor and software**.
   - Source: [BC-0484EN](https://docs.broadcom.com/doc/BC-0484EN)

2. **Classic PLX multi-host (Gen2/Gen3) is the conceptual ancestor.**
   On PEX8734 / PEX8664 product briefs:

   - Legacy **single-host** vs **multi-host** modes.
   - In multi-host mode, *“a virtual switch is created for each host port
     and its associated downstream ports”*; traffic between VS instances
     is isolated.
   - Hosts communicate via doorbells for failover (1+1 / N+1).
   - Config via strapping pins, EEPROM, I2C, or host software.

   This is the public description of the VS model. Atlas runtime registers
   (VS Enable 0–3, per-VS upstream, VS0 Port Vector) are the Gen4
   elaboration of that model.
   - Sources:
     [PEX8734 brief](https://docs.broadcom.com/doc/12351853),
     [PEX8664 brief](https://docs.broadcom.com/doc/12351840)

3. **VS1–VS3 Port Vector registers: still not found in public sources.**
   No product brief, forum dump, or FreeBSD/Linux driver names VS1–VS3
   port-vector CSRs for Atlas. **UNKNOWN** whether:

   - membership is only explicit for VS0 (bitmap at `0xe0–0xe3` /
     `0x380–0x38c`) and VS1–3 are synthetic-FW-only; or
   - VS1–3 vectors exist under different PDE names / port pages; or
   - ports not claimed by VS0 are reassigned by firmware routing tables
     in Synthetic mode.

4. **VS1/2/3 Upstream 32-bit encoding: UNKNOWN for Atlas.**  
   VS0 Upstream is fully structured (USP, NT, NT2, DMA, VC, ALUT enables).
   VS1–3 are labeled only as full 32-bit “Upstream Port” in the vendor
   database (already known). Public docs never decode those dwords.
   **Hypothesis (unconfirmed):** same bit layout as VS0 reused for VS1–3,
   with PDE missing field names — testable by live read/write once
   multi-host is enabled, but **not confirmed**.

5. **Synthetic vs Base mode changes who programs the hierarchy.**  
   Capella brief (and Serial Cables Atlas2 manuals) distinguish:

   - **Base:** no FW involvement; fan-out; SBR-driven.
   - **Synthetic:** embedded CPU is the host of the fabric and
     synthesizes hierarchy for each connected host from firmware.

   Multi-host I/O sharing on Atlas-class silicon is marketed primarily as
   a **software-defined / synthetic** feature, not as pure SBR VS vectors.
   - Sources: BC-0484EN; [PEX89000 brief](https://docs.broadcom.com/doc/PEX89000-Managed-PCI-Express-5.0-Switches);
     Serial Cables Atlas2 ITAP manual (`fdl sbr` = base, `fdl fw` = synthetic).

### Practical implication for `pexctl`

Runtime CSR programming of VS Enable + VS0 Upstream + VS0 Port Vector +
Config Release is the only publicly grounded path for **base multi-host**.
Full VS1–3 membership and Synthetic routing tables remain **OEM-SDK /
NDA** territory.

---

## Q3. “Atlas mode” (SoC dword 3 bits 17:16) and STRAP_FANOUT_EN (bit 20)

### Findings

**Exact bit encoding of Atlas mode [17:16] and STRAP_FANOUT_EN: UNKNOWN
in public docs** (no strap table published).

**Public boot / operation modes *do* exist and map cleanly onto those
straps at a semantic level:**

From **BC-0484EN — Switch Operation Modes**:

| Mode | Public description |
|------|--------------------|
| **Base Mode** | No FW involvement; embedded CPU can be disabled; device operates as a **standard PCIe fan-out switch**. |
| **Base with MPT Mode** | Base fan-out plus **MPT endpoint** for NVMe / chassis management. |
| **Synthetic Mode** | Embedded CPU synthesizes hierarchy from the host point of view. |

Capella (PEX89000) collapses this to two named modes (**Base** and
**Synthetic**) with the same fan-out vs CPU-synthesized hierarchy story,
and states configuration via **serial EEPROM, embedded CPU, and/or host
software**.

Serial Cables operational mapping (Atlas Gen4 + Atlas2 Gen5):

| Mechanism | Mode |
|-----------|------|
| `fdl sbr` / SBR flash image | **Base switch mode** |
| `fdl fw` / FW image | **Synthetic mode** |
| Blue heartbeat LED solid ON (Atlas2) | Base fan-out |
| Blue heartbeat LED **blinking** (Atlas2) | Synthetic |

- Sources: BC-0484EN; PEX89000-PB102; Serial Cables Atlas2 ITAP User’s
  Manual ([example PDF](https://serialcables.com/vendor-media/extra/upload/media/studio_672b8f6ce98be8794561730911612.pdf?title=User's%20Manual&proId=74));
  STH SerialCables thread.

### Hypotheses for strap bits (unconfirmed)

| Field | Likely role | Confidence |
|-------|-------------|------------|
| `STRAP_FANOUT_EN` (bit 20) | Asserts Base / pure fan-out path (CPU optional/disabled for data plane) | Medium (name + Base-mode marketing) |
| Atlas mode [17:16] | Selects among Base / Base+MPT / Synthetic / reserved | Low–medium (2 bits, 3 public modes) |

**Do not program these bits without NDA strap tables or side-by-side SBR
diffs of known Base vs Synthetic images.**

Live Strix-4 note (already known): fan-out board has fanout **clear** in
current SBR expert fields — so either fanout is default-strapped in
hardware, or Base fan-out does not require the named bit set. That
tension remains **open**.

---

## Q4. Multi-host bring-up sequence; Config Release (`0xeb` / `0x3ac`); clocking

### Findings

1. **Config Release / Initiate Configuration**  
   Public docs never name dword `0xeb`. Role as **commit / release** after
   VS programming is an internal PDE label only. **Semantics beyond
   “probable commit trigger”: UNKNOWN.**  
   Related public idea: multi-host and synthetic fabrics are programmed
   then left in hardware data path without FW per packet (BC-0484EN
   “Software Defined PCIe Switch Fabric”).

2. **Bring-up order from public sources (coarse):**

   | Step | Source of truth |
   |------|-----------------|
   | Power sequence, refclks stable before PERST# deassert | General PCIe switch design practice; secondary design blogs stress multi-rail sequencing for PEX88096 (treat as non-primary). |
   | Load SBR (or hold SBR disabled via board strap/jumper) | Serial Cables J2: *Disable Atlas loading SBR* |
   | Base: SBR sets stations / USP / clocking image | Serial Cables `fdl sbr`, setmode → cold reset |
   | Synthetic: FW image + embedded CPU | Serial Cables `fdl fw` |
   | Runtime: VS enables, upstreams, port vectors, NT/ALUT | Runtime CSR map (internal); classic PLX multi-host order is EEPROM/I2C then host SW |
   | Host enumeration / optional hot-add | Standard PCIe; DPC/eDPC marketed for error isolation |

3. **Clocking requirements for multi-host**  
   - Separate hosts almost always mean **separate refclk domains** →
     **SRIS or SRNS per port**, not a single common clock across hosts.
   - Product briefs advertise **SSC isolation** and **SRIS/SRNS**.
   - Serial Cables modes always pair width with I/N (SRIS/SRNS); config
     names include `HOST_X4_SRIS`.
   - Board-level: each host-facing port needs its own refclk generation
     or independent SSC-tolerant SerDes mode; shared common clock across
     two root complexes is generally wrong for multi-host.

4. **External management requirement**  
   BC-0484EN Figure 3 caption area: complex multi-host / multi-switch
   topologies require *“an external management processor and software”*.
   That is the vendor-intended control plane for true multi-host, not
   pure host-side poke of a few CSRs from one root complex alone.

**Citations:** BC-0484EN; PEX89000 brief; Serial Cables Gen4/Gen5 manuals;
STH thread.

---

## Q5. NT (non-transparent) configuration; ALUT; drivers

### Findings

1. **NT2.0 on PEX88000**  
   BC-0484EN: *Enhanced Non-Transparent Bridging 2.0 (NT2.0)*; largest
   device has **48 NT2.0-capable ports**; multi-host enabling architecture
   shipped since 2004, enhanced to NT2.0. Also: general-purpose **DMA**
   (up to 48 channels/functions), **TWC** (Tunneled Window Connection)
   for short host-to-host packets.

2. **NT-Virtual vs NT-Link roles**  
   Public **Atlas** docs do not define these names. FreeBSD
   `ntb_hw_plx(4)` (Gen3 PLX) **does**:

   - **NT Link** interface: visible from Root Port side  
     (PCI IDs `10b5:87a0` NT0 Link, `10b5:87a1` NT1 Link)
   - **NT Virtual** interface: other side  
     (`10b5:87b0` NT0 Virtual, `10b5:87b1` NT1 Virtual)
   - Modes: **NTB-to-NTB (back-to-back)** vs **NTB-to-Root Port**
   - **A-LUT (Address Lookup Table):** when enabled, BAR2 can split into
     up to **128** memory windows (`hint.ntb_hw.X.split`)
   - Scratchpads (6 or 12), doorbells (16), up to 2×64-bit or 4×32-bit
     memory windows without ALUT

   Atlas runtime already exposes **NT Port + NT2 Port + ALUT NT / ALUT NT2
   enables** on VS0 Upstream — conceptual continuity with dual-NT + ALUT,
   **register map is not the FreeBSD Gen3 map**.

   - Source: [ntb_hw_plx(4)](https://man.freebsd.org/cgi/man.cgi?query=ntb_hw_plx&sektion=4&manpath=FreeBSD+13.1-RELEASE+and+Ports)
   - Source: FreeBSD `sys/dev/ntb/ntb_hw/ntb_hw_plx.c` (IDs above; ALUT
     programming at offsets such as `0xc3c`, link/virtual bases
     `0x3E000` / `0x3C000` — **Gen3 only**)

3. **Linux mainline**  
   - **No** `ntb_hw_*` driver for Atlas / `1000:c010` in mainline (as the
     brief states).
   - Historical RFC for `ntb_hw_plx` on Linux (2021) targeted classic PLX
     NTB; **not merged as a general Atlas driver**.
   - FreeBSD is the only production open NTB driver for PLX-class NTB,
     and only for **PEX 8713/8717/8725/8733/8749** (and “compatible”
     Gen3). **No Atlas DID listed.**

4. **Management endpoint vs NTB endpoint**  
   Linux `mpt3sas` defines  
   `MPI26_ATLAS_PCIe_SWITCH_DEVID (0x00B2)` — *“Atlas PCIe Switch
   Management Port”*. Field reports of Serial Cables cards exposing
   `/dev/mpt3ctl` + SES match **MPT management**, not NTB transport.
   - Source: Linux `drivers/scsi/mpt3sas/mpt3sas_base.h`

5. **Vendor / OEM path for NT+ALUT on Atlas**  
   Broadcom public **PCI/PCIe SDK** page still exists (legacy PLX SDK
   packaging: drivers, GUI). Whether current SDK packages include
   PEX88000 NT2.0 ALUT APIs is **UNKNOWN without download agreement /
   partner access**. Public stackoverflow / github mirrors discuss older
   PLX SDK (`/dev/plx`), not Atlas NT.

   ExpressFabric multi-host software packages are described as available
   **through third-party vendors** for complex topologies (BC-0484EN).

6. **Secondary sources claiming `switchtec` drives PEX88096 are wrong.**  
   AIChipLink-style blog posts conflate Broadcom Atlas with Microchip
   Switchtec. Atlas management is **MPT / embedded ARM Cortex-R4 /
   Broadcom SDK**, not Switchtec PSX. Treat such blogs as **unreliable**
   for driver selection.
   - Example of conflation: [aichiplink SS02-0B00-02 guide](https://aichiplink.com/blog/SS02-0B00-02-Broadcom-PEX88096-PCIe-Gen4-Switch-Guide_1159)

### Summary table

| Layer | Atlas status |
|-------|--------------|
| Hardware NT2.0 + dual NT + ALUT enables | Documented in brief + runtime CSR names |
| Public ALUT programming recipe for Atlas | **UNKNOWN** |
| FreeBSD `ntb_hw_plx` | Gen3 only; conceptual reference |
| Linux mainline NTB | **None** for Atlas |
| Out-of-tree Broadcom NTB for Atlas | **Not found** in public search |
| Management (MPT `1000:00b2`) | Present in mpt3sas headers / field reports |

---

## Q6. Persistence: can VS/NT/multi-host boot without host software?

### Findings

1. **Dedicated SBR SoC fields for VS/NT: none found publicly**  
   Aligns with internal audit (vendor `AtlasSBR.db` has no VS/port-vector/
   NT fields). Multi-host is not a simple SoC strap like upstream port.

2. **Vendor-intended configuration channels (public):**  
   Capella brief: *“Configurable with serial EEPROM, embedded CPU, and/or
   host software.”*  
   Atlas brief: SDK + third-party packages for multi-host; Synthetic mode
   uses embedded CPU + FW; Base mode is SBR fan-out.

3. **SBR *does* persist Base-mode topology** (stations, USP, SRIS/SRNS
   images, etc.). Serial Cables:

   - `fdl sbr` → flash SBR, **base switch mode**
   - `setmode` → writes mode into Atlas, **cold power cycle** required
   - J2 jumper can **disable SBR load** for recovery / debug

4. **Synthetic multi-host hierarchy is FW-persistent**, not SBR-field
   persistent: `fdl fw` programs switch FW (Synthetic). Heartbeat LED
   distinguishes Synthetic vs Base on Atlas2 cards.

5. **PSB register-write records as multi-host bake path**  
   Mechanism exists (known): PSB can write arbitrary runtime CSRs by
   dword address. In principle VS Enable / Upstream / Port Vector /
   Config Release **could** be applied pre-enumeration from SBR.  
   **No public vendor example** of a multi-host PSB image was found.
   **Vendor-intended for complex multi-host remains: embedded CPU FW +
   external management SW**, not hobbyist PSB-only.

6. **Community consensus**  
   STH: multi-host fabric tools *“restricted only to OEMs”* for ebay /
   mortals class hardware.

### Answer

| Goal | Vendor-intended persistence |
|------|----------------------------|
| Fan-out / station map / SRIS-SRNS base image | **SBR** (`fdl sbr` / setmode / SPI) |
| Synthetic hierarchy / shared I/O fabric | **Switch FW + embedded CPU** (`fdl fw`) |
| Runtime VS/NT poke from host | Host software / SDK after boot |
| VS/NT via PSB write records | **Technically plausible, not publicly documented as the flow** |

---

## Q7. Register manuals, datasheets, SDK UGs, errata (accessibility)

### Accessible without NDA

| Document | Status | URL |
|----------|--------|-----|
| PEX88000 Series product brief BC-0484EN | **Public PDF** | https://docs.broadcom.com/doc/BC-0484EN |
| PEX89000 Series product brief (Capella) | **Public PDF** | https://docs.broadcom.com/doc/PEX89000-Managed-PCI-Express-5.0-Switches |
| PEX88096 product web page | Marketing only | https://www.broadcom.com/products/pcie-switches-retimers/expressfabric/gen4/pex88096 |
| PCI-SIG product wall blurb | Marketing | https://pcisig.com/pex88000-pcie-gen4-switch |
| Older multi-host whitepaper (2004, PLX NTB intro) | Public | https://docs.broadcom.com/doc/12354747 |
| Gen2/Gen3 multi-host product briefs (VS concept) | Public | e.g. https://docs.broadcom.com/doc/12351853 |
| Serial Cables Atlas / Atlas2 host-card manuals | Public OEM PDFs | serialcables.com product media; ManualsLib mirrors |
| FreeBSD ntb_hw_plx man + source | Public | man.freebsd.org; freebsd-src |
| Broadcom PCI/PCIe SDK download page | Public landing; package under click-through | https://www.broadcom.com/products/pcie-switches-retimers/software-dev-kits |

### Not found publicly (treat as NDA / partner-portal only)

| Document | Search result |
|----------|---------------|
| **RM109** (rumored PEX88000 register manual) | **No public hit** on Broadcom docs, archive.org, forums, reseller mirrors |
| **UG100** (rumored SDK user guide) | **No public hit** |
| PEX88096 full datasheet / electrical design guide | **Not public**; only product brief |
| PEX88000 errata | **Not public** |
| ExpressFabric multi-host programming guide | **Not public**; “third-party vendors” + OEM |

**Conclusion:** There is still **no accessible copy** of a true Atlas
register manual or full datasheet. Product briefs + OEM host-card manuals
+ reverse PDE work remain the best open sources. RM109/UG100 naming is
**unconfirmed** outside internal rumors.

---

## Q8. Field reports (multi-host, NTB, upstream moves, concrete values)

### Level1Techs “Neverending Story”

Thread: [A Neverending Story: PCIe 3.0/4.0/5.0/6.0…](https://forum.level1techs.com/t/a-neverending-story-pcie-3-0-4-0-5-0-6-0-sci-fi-bifurcation-adapters-switches-hbas-cables-nvme-backplanes-risers-extensions-the-good-the-bad-the-ugly-will-there-be-a-final-solution/171428)

**Extracted concrete observations:**

- Multiple users run **PEX88048 / PEX88096** Chinese GPU/NVMe plates in
  **fan-out** successfully (Gen4 x16 uplink, multi-x16 or multi-x4 down).
- Example topology dumps show `Broadcom / LSI PEX880xx PCIe Gen 4 Switch
  (rev b0)` bridges with Port #0 ×16 and Port #n ×4 — transparent tree only.
- **Firmware modes** advertised on Taobao/Ali boards as e.g. `5x16`,
  `12x4`, `6x8`, `3x16` — bifurcation presets, not multi-host.
- **DIP switches** on some SlimSAS 88096/88048 cards select bifurcation
  (preferred over flash-only mode cards) — post ~902 era reports.
- **No multi-host / NTB success report with register values** found in
  sampled pages of that thread. Discussion of EPYC NTB as *alternative*
  switch appears as curiosity, not Atlas NTB bring-up.
- PLX “picky about firmware” comments refer mostly to older PLX/HBA
  ecosystem, not Atlas SBR layout.

### ServeTheHome

1. [PEX88000 & PEX9700 interest thread](https://forums.servethehome.com/index.php?threads/broadcom-pex88000-pcie4-pex9700-pcie3.28501/)  
   — Feature interest (TWC, DMA, SR-IOV VF remapping); **no register
   recipes**. Notes P411W-32P / PEX88048 hardware scarcity.

2. [SerialCables PCI4-AD-x16HE-BG4](https://forums.servethehome.com/index.php?threads/help-with-serialcables-com-pci4-ad-x16he-bg4.47497/)  
   **Highest-value field report for open tooling:**

   | Detail | Value |
   |--------|-------|
   | Chip | Broadcom Atlas B0 |
   | Management | MCU + USB CDC CLI; `/dev/mpt3ctl` + SES |
   | Base config flash | `fdl sbr` + `B0 HOST_X4_SRIS_V02.bin` |
   | Synthetic FW flash | `fdl fw` |
   | Bifurcation | `setmode` 1–8 (I/N = SRIS/SRNS) on rev 1.1; broken CLI on some 1.2 |
   | Recovery | Jumper USB boot; reflash real FW if bad BIN as FW |
   | Sideband I2C | `ATLAS_SCL` / `ATLAS_SDA` on SFF-8644 sideband |
   | UART | CN1 SDB UART, CN2 Atlas UART |
   | BAR issues | Extra synthetic buses consume host MMIO; bare switches better |
   | Multi-host | Explicitly “OEM tools only” for fabric sharing |

### OSHWHub / Chinese open hardware

- Project: [PEX88096-PCIE4-Switch-GPU底板套件](https://oshwhub.com/eda_nrhnxjzuv/pex88096-pcie4-switch-gpu-basepl)  
  (KCORES / eda_nrhnxjzuv) — open GPU baseplate; derivative
  [PEX88064 AIC](https://oshwhub.com/eda_nrhnxjzuv/kcores_pex88064_aic_gen4_6slimsas).
- Already referenced in tree notes for Device Editor screenshot / all-x16
  SBR attachment. **No public multi-host or NT EEPROM dump** extracted
  from project page in this pass (page fetch unstable).

### Reddit / other

- LocalLLaMA / homelab: PEX88096 used as transparent GPU/P2P fabric
  behind one host — no multi-host.
- GitHub NCCL issue: virtual PCI bridges of PEX88096 confuse topology
  XML — again transparent multi-port, not NTB.

### Concrete register/EEPROM values from the wild

| Item | Concrete? |
|------|-----------|
| Multi-host VS port vectors | **None published** |
| NT ALUT entries | **None for Atlas** |
| Upstream port moves via SBR | Community does bifurcation/firmware modes; USP move not documented in field dumps |
| DIP bifurcation | Present on some Ali boards; mapping **board-specific, not published as SBR offsets** |
| Serial Cables mode images | Named `HOST_*_SRIS_*.bin` — binary not reverse-published here |

---

## Q9. Management / OOB interfaces; Serial Cables; bad-flash recovery

### Findings (strong)

**Serial Cables Atlas Gen4 host card (`PCI-AD-x16HE-BG4`):**

| Interface | Details |
|-----------|---------|
| **USB CDC CLI** | Micro USB; VID `03EB` PID `2018` (Atmel/Microchip USB); 115200 8N1 on Atlas2 manuals |
| **Atlas UART** | CN2: TX/RX/GND — “Header for Atlas UART (Required FW)” |
| **SDB UART** | CN1: TX/RX/GND — “Atlas SDB UART” |
| **I2C / SMBus sideband** | `ATLAS_SCL` / `ATLAS_SDA` on SFF-8644 sideband pins (C1/C2 in SC mode table) |
| **Sideband modes** | PCI-SIG / SerialCables / UTran / SB (slide switch); host reset required |
| **SBR disable jumper J2** | ON = **Disable Atlas loading SBR** — primary bad-config recovery |
| **MCU USB boot J3 / J78** | MCU FW recovery paths |
| **CLI** | `dr` dump switch regs, `dp` dump port regs, `df` dump flash, `setmode`, `showport`, `scan` (I2C bus scan), `fdl sw` (older), `fdl sbr/fw/mfg` (newer) |
| **LEDs** | Blue heartbeat, red error |

**Atlas2 (Capella Gen5) Serial Cables manuals add:**

| Command | Function |
|---------|----------|
| `mw <reg> <data>` | **Write any 32-bit switch register** |
| `dr` / `dp` / `df` | Dump reg / port / flash |
| `fdl sbr\|fw\|MCU` | Base SBR / Synthetic FW / MCU |
| `spread` | SSC −0.3% / −0.5% to switch |
| `clk` | Enable/disable refclk outputs to ports |
| `bist` | On-board I2C diagnostics |
| Heartbeat LED | Solid = Base fan-out; **Blink = Synthetic** |

- Sources: Serial Cables PCI-AD-x16HE-BG4 manual; Atlas2 ITAP manual PDF
  above; STH thread.

### SMBus / I2C slave address

**Exact Atlas I2C/SMBus 7-bit slave address: UNKNOWN** in public docs.  
Sideband wires are confirmed (`ATLAS_SCL`/`ATLAS_SDA`). Internal field
`legacy_plx_i2c_target_enable` exists in SoC catalog (tree notes) —
suggests a PLX-compatible I2C target, but address table is NDA/design-guide
material. Older PLX switches commonly used I2C for config; pattern likely
continues.

### MDIO

**Not evidenced** for Atlas management in public materials searched.
**UNKNOWN / likely N/A** as primary control plane.

### Management PCIe ports

BC-0484EN: **two additional management ports for mCPU**; product page
table lists **two ×1 dedicated management ports**. Matches dual-mgmt /
redundant management CSR fields already known.

### Bad-flash recovery recipe (OEM-board pattern)

1. Hardware: assert **SBR load disable** jumper (Serial Cables J2) → boot
   without bad SBR.
2. MCU USB / CDC CLI still available if MCU flash intact.
3. Reflash known-good **SBR** (`fdl sbr`) or **FW** (`fdl fw`).
4. Optional: TTL UART to Atlas SDB/UART headers for low-level console
   when FW supports it.
5. SPI direct program of CS0 (in-band or clip) remains the nuclear option
   for boards without Serial Cables MCU (Strix-class).

**Note:** Writing a Synthetic FW image while the card expects Base SBR
(or vice versa) has **bricked field units** until correct image class
restored (STH).

---

## Q10. Cross-family transferability: PEX89000 Capella vs Atlas

### Findings

| Topic | Transfer quality |
|-------|------------------|
| Operation modes Base / Synthetic | **High** — Capella docs clearer; same vocabulary; Serial Cables uses same `fdl sbr` / `fdl fw` split on Atlas2 |
| Multi-host + I/O sharing marketing model | **High** — Capella brief re-states 2010 multi-host introduction, dynamic I/O allocation |
| NT2.0 | **Medium** — Capella largest part has **8** NT ports vs Atlas **48**; same NT2.0 brand, different scale |
| SRIS/SRNS / SSC isolation | **High** — Capella states explicitly; Atlas implies via acronyms + OEM modes |
| Embedded ARM management CPU | **High** |
| Secure Boot / attestation | Capella emphasizes more; Atlas has `-02` secure boot OPNs |
| On-chip PCIe analyzer | Capella feature; Atlas brief less loud |
| VS register map (VS0 vector, etc.) | **UNKNOWN if identical** — no Capella register manual public either |
| DMA channel count | Atlas marketed up to 48; Capella brief less specific on 48 |
| Documentation availability | **Slightly better Capella narrative** in PB102, but **still no RM**; Serial Cables Atlas2 manuals denser for OOB than pure Broadcom PDFs |

### Transfer strategy for `pexctl`

1. Treat Capella Base/Synthetic + SBR-vs-FW split as **authoritative
   vocabulary** for Atlas straps/modes.
2. Do **not** assume VS CSR addresses transfer without PDE for Capella.
3. Serial Cables Atlas2 `mw`/`dr` path is a live lab for Capella CSR
   experiments if hardware is available — may illuminate Atlas by
   analogy only after address map comparison.

**Citations:** PEX89000-PB102 (2023-10-26); BC-0484EN; Serial Cables
Atlas2 manuals.

---

## SURPRISES / LEADS

1. **Serial Cables is the richest open Atlas lab environment** — USB CLI,
   `dr`/`dp`/`df`/`mw`, SBR disable jumper, SRIS-named SBR images, Base vs
   Synthetic LED semantics on Atlas2. Higher yield than hunting NDA PDFs.

2. **Blue heartbeat LED encodes Base vs Synthetic on Atlas2** (solid vs
   blink). Useful for field forensics without a CLI.

3. **`B0 HOST_X4_SRIS_V02.bin` naming** is the strongest public evidence
   that **SRIS is an SBR-level attribute**, not only a runtime CSR —
   primary lead for reverse-diffing Clocking-mode bits once two SBR images
   (SRIS vs SRNS) of the same bifurcation are obtained.

4. **FreeBSD `ntb_hw_plx` remains the only open ALUT/NT programming
   reference**, but device IDs are classic PLX `10b5:87a*/87b*` — porting
   to Atlas `1000:c010` NT endpoints would be a new driver project, not a
   enablement flag.

5. **aichiplink / similar OEM blogs mis-attribute Switchtec drivers to
   Broadcom Atlas** — dangerous for software planning; ignore for NTB
   driver selection.

6. **Management DID `1000:00b2`** (`MPI26_ATLAS_PCIe_SWITCH_DEVID`) is a
   concrete handle for mpt3sas / SES tooling on boards that expose the
   MPT management endpoint (Serial Cables confirmed).

7. **PSB as multi-host persistence** is still the best *open* theory for
   boot-time VS/NT without Synthetic FW, but **zero public multi-host PSB
   examples** — obtaining one OEM multi-host SBR image would unlock more
   than another product brief.

8. **DIP-switch bifurcation boards** on AliExpress are pure fan-out
   convenience; they do not indicate multi-host silicon config is exposed
   to end users.

9. **Broadcom docs portal still only publishes 4-page product briefs** for
   the whole PEX88000/89000 managed lines. RM109/UG100 remain **mythical
   in open search** as of 2026-07-29.

10. **Lead experiment for Q1:** acquire Serial Cables `HOST_*_SRIS_*.bin`
    and `HOST_*_SRNS_*.bin` (or dump flash after `setmode` I vs N), then
    byte-diff SBR Clocking-mode dwords 33–39. That is the highest-ROI
    public path to enum meanings without NDA.

---

## Confidence summary

| Q | Status |
|---|--------|
| Q1 Port Type / Clocking enums 0–3 | **UNKNOWN** exact; SRIS/SRNS are real modes; 0 = production default |
| Q2 VS1–3 membership + upstream encoding | **UNKNOWN** detail; VS isolation model citable from Gen3 briefs |
| Q3 Atlas mode / FANOUT_EN | **UNKNOWN** bits; Base / Base+MPT / Synthetic modes public |
| Q4 Bring-up + 0xeb | Coarse sequence public; **0xeb semantics unconfirmed** |
| Q5 NT/ALUT/drivers | NT2.0 + dual NT public; **no Atlas NTB driver**; FreeBSD Gen3 reference |
| Q6 Persistence | SBR = Base; FW = Synthetic; PSB plausible; OEM SW for fabric |
| Q7 Manuals | **Only product briefs public**; RM/UG/datasheet NDA |
| Q8 Field reports | Fan-out abundant; multi-host/NT **absent** with registers |
| Q9 OOB | **Strong** Serial Cables UART/I2C/USB/jumper map |
| Q10 Capella transfer | Modes/clocking **transfer**; CSR map **unproven** |

*Report date: 2026-07-29. Agent: Grok research pass for pexctl / Strix-4.*
grok exit=0
