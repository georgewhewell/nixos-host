# PEX88096 research brief (shared across research agents)

You are one of several independent research agents investigating the Broadcom/PLX
**PEX88096** ("Atlas", PEX88000 family, PCIe Gen4, 98-lane switch, PCI ID
1000:c010, rev B0). We are building an open-source configuration tool
(`pexctl`) for it. Your job: find NEW, citable information for the OPEN
QUESTIONS below. Do NOT re-derive what we already know (listed at the bottom).
Prefer primary sources: Broadcom docs, SDK material, register manuals, driver
source, forum field-reports with concrete register/EEPROM details. Cite every
claim with a URL or document name. Explicitly mark anything you could not
confirm as UNKNOWN. Web search is expected; use sub-agents if your tool has them.

## OPEN QUESTIONS (in priority order)

Q1. SBR "Port Type" (2-bit per port, ports 0–95/116/117, SoC dwords 25–32) and
    "Clocking mode" (2-bit per port, SoC dwords 33–39) field ENUM MEANINGS.
    All reference images hold zero. What do values 0–3 mean for each?

Q2. Virtual-switch (multi-host) programming model: how is port membership set
    for VS1–VS3? We found a "VS0 Port Vector Register" (0xe0–0xe3) but no
    VS1–VS3 vector registers. Also: encoding of "VS1/2/3 Upstream Register"
    (full 32-bit fields, vs VS0's structured [7:0] port + NT fields).

Q3. Semantics of SBR "Atlas mode" (2 bits, SoC dword 3 bits 17:16) and
    "STRAP_FANOUT_EN" (bit 20): what boot modes exist (fan-out, VS/synthetic,
    NT) and which values select them?

Q4. Multi-host bring-up sequence on Atlas: which registers in which order;
    role of "Config Release Register / Initiate Configuration" (dword 0xeb,
    bit 0); clocking requirements per port (SRIS/SRNS/common) and board-level
    implications for multi-host use.

Q5. NT (non-transparent) port configuration on Atlas: NT-virtual vs NT-link
    roles, ALUT (address LUT) programming, BAR translation windows, and any
    existing Linux/Windows driver support (mainline ntb_hw_* has no Broadcom
    Atlas driver — is there an out-of-tree one, or Broadcom reference code?).

Q6. Persistence: can VS/NT/multi-host configuration be baked into the SBR so
    the switch boots multi-host without host software? Candidates: PSB
    register-write records, "CCR register update" programs in SoC dwords
    7–24/41–49, or vendor host drivers. What is the vendor-intended flow?

Q7. Locate any accessible copy of: PEX88000 register manual ("RM109"?),
    PEX88096 datasheet, PEX88000/89000 SDK user guide (UG100?), design guides,
    errata. Mirrors, forum attachments, resellers, archives all count.

Q8. Real-world field reports of multi-host, NTB, or upstream-port moves on
    PEX880xx (Level1Techs "neverending story" thread, ServeTheHome, Reddit,
    Chinese forums/boards, OSHWHub/EasyEDA PEX88096 projects). Extract any
    concrete register values, EEPROM byte offsets, or DIP/strap details.

Q9. Atlas management/out-of-band interfaces: I2C/SMBus slave (address?),
    UART console, MDIO; the "Serial Cables" Atlas host card management
    interface; anything useful for out-of-band recovery of a bad flash.

Q10. Cross-family transferability: how similar are PEX89000 (Capella, Gen5)
    VS/multi-host registers to Atlas? Is Capella documentation more available
    and does it document the VS model in a way that transfers?

## WHAT WE ALREADY KNOW (do not redo)

- SBR (serial boot ROM) container at SPI flash offset 0x400: signature
  0xc0103dc4, 22-dword index, 104-dword SoC settings region, PSB /
  PSB-SerDes write-record blocks, PSW lane blocks, checksum
  (0 - (0xa5 + sum) mod 256).
- SoC dword 0: STRAP_UPSTRM_PORT [7:0], max link speed [9:8] (0-3=Gen1-4),
  lane-enable [15:13], then 24 packed 3-bit station quarter codes
  (0=x16, 1=x4, 7=disabled; RDK proves [1,1,1,1]=x4x4x4x4, [1,1,7,7] mixed).
- SoC dword 3: Station DPR enable [13:8], "Atlas mode." [17:16],
  auto-link-train bit 18, STRAP_GEN1_COMPLIANCE_N 19, STRAP_FANOUT_EN 20,
  PLLBYPASSMODE 21, STP_BYPASS 22, FlashSigEn 30, SioBClkOEn 31.
- Vendor template defaults: all quarter codes 1 (x4x4x4x4 fallback), Gen3,
  upstream port 0, VS0 enabled.
- Runtime CSRs (port-0 page, byte offset = dword index * 4, port CSRs at
  BAR0 0x800000): Port Configuration 0-2 (0xc0-0xc2, 12 bits per station),
  Clock Enable 0-3 (0xc3-0xc6), Non Volatile Memory Data/Control
  (0xd0/0xd1), Chip Bring up Control (0xd3: Upstream Hot Reset Cntrl bit 2,
  disable SBR load on lvl1 bit 3), Debug Control (0xd4: Cut through Enable
  bit 11, Switch Mode bit 30), Management Port Control (0xd5: active +
  redundant mgmt port), VS Enable (0xd6: VS0-3 enables), VS0 Upstream (0xd8:
  upstream port [7:0], NT port [12:8] + enable 13, NT2 port [20:16] +
  enable 21, DMA mode 24, VC mode 25, ALUT NT enable 30, ALUT NT2 enable 31),
  VS1-3 Upstream (0xd9-0xdb, 32-bit), VS0 Port Vector (0xe0-0xe3, 98-bit
  bitmap), VS PERSTn Status (0xea: per-VS and NT1-0 PERSTn value/control),
  Config Release (0xeb: Initiate Configuration bit 0).
- Per-station Physical Layer Command/Status register (0x87): upstream and
  downstream crosslink enable bits (default 1).
- Live board state: fan-out, upstream port 0, all stations x16, all
  Port Type/Clocking fields 0; BlueField-2 NIC on port 16, ASUS Hyper M.2
  NVMe carrier on port 64 (station 4).
- The vendor PDE (Java) contains no enum labels for Port Type/Clocking mode
  and no auto-derivation between upstream port and those tables.
- Broadcom product brief BC-0484EN mentions up to 48 DMA channels for
  host-to-host transfers; family sold as "ExpressFabric"; feature tables
  list NT ports, Shared I/O, SRIS/SRNS, embedded CPU.

## OUTPUT

Write your findings as Markdown to the file path given in your task prompt.
Structure: one section per question (Q1..Q10) with findings + citations, then
a final "SURPRISES / LEADS" section for anything valuable outside the
questions. If a source requires login/NDA, say so explicitly.
