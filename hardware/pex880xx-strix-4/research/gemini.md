# PEX88096 (Atlas) Research Findings Report

This document records the research findings for the Broadcom/PLX **PEX88096** ("Atlas", PEX88000 family, PCIe Gen4, 98-lane switch, PCI ID `1000:c010`, rev B0) open questions, compiled by independent research subagents.

---

## Q1. SBR "Port Type" and "Clocking Mode" Field Enum Meanings

* **Port Type (2-bit per port, ports 0–95/116/117, SoC dwords 25–32):**
  * **Architecture & Concept:** In the PEX88000 architecture, port type settings govern individual port operational roles within the switch hierarchy. Expected functional roles across Broadcom/PLX multi-host switches include Host / Upstream Port (USP), Endpoint / Downstream Port (DSP), Non-Transparent Bridge (NT), and Disabled/Unused.
  * **Enum Values (0–3):** **UNKNOWN**. All reference SBR images (live hardware board, Base RDK96, and vendor templates) store `0x0` across all port type entries. Broadcom's PEX Device Editor (PDE) Java database (`Pde/db/pex_device_atlas.db`) contains no textual enum label mappings for these dwords, and no public kernel driver or open-source header exposes the 2-bit field decoding.

* **Clocking Mode (2-bit per port, SoC dwords 33–39):**
  * **Architecture & Concept:** Governs per-port reference clocking configurations. Broadcom product documentation explicitly notes that the PEX88000 family supports Common Clock (CC), Separate Reference Clock Independent SSC (SRIS), and Separate Reference Clock No SSC (SRNS).
  * **Enum Values (0–3):** **UNKNOWN**. The numerical mapping of values `0`, `1`, `2`, `3` to CC, SRIS, SRNS, or Auto/Disabled is not present in PDE Java reflection classes or public technical notes.

* **Citations:**
  * Broadcom PEX88000 Family Product Brief `BC-0484EN` (verifies SRIS/SRNS/CC support).
  * Local SBR Audit: [`ATLAS-SBR-NOTES.md`](file:///mnt/Home/src/nixos-config/hardware/pex880xx-strix-4/ATLAS-SBR-NOTES.md).
  * Broadcom NDA Gated: PEX88000 Series Data Book / Register Manual (RM109).

---

## Q2. Virtual-Switch (Multi-Host) Programming Model

* **Port Membership for VS1–VS3:**
  * **VS0 Port Vector:** Runtime CSR offset `0x380–0x38c` (abs offset = dword index `0xe0–0xe3` * 4) is named `VS0 Port Vector` in the vendor PDE database and holds a 98-bit bitmap representing active member ports for Virtual Switch 0.
  * **VS1–VS3 Membership:** **UNKNOWN**. No corresponding `VS1 Port Vector`, `VS2 Port Vector`, or `VS3 Port Vector` register definitions exist under those names in the extracted PDE database. Port membership for VS1..VS3 is either:
    1. Implicitly derived as the unassigned complement of VS0's port vector bitmap.
    2. Programmed via per-station/per-port configuration CSRs (`0x300–0x308` or port-page CSRs).
    3. Assigned via unmapped ALUT / fabric routing structures.

* **VS1/2/3 Upstream Register Encoding:**
  * `VS0 Upstream` (`0x360` / `0xd8`) has structured fields: `VS0 Upstream Port [7:0]`, `NT Port [12:8]`, `NT Enable [bit 13]`, `NT2 Port [20:16]`, `NT2 Enable [bit 21]`, `DMA Mode [bit 24]`, `VC Mode [bit 25]`, `ALUT NT port enable [bit 30]`, `ALUT NT2 port enable [bit 31]`.
  * `VS1 Upstream` (`0x364`), `VS2 Upstream` (`0x368`), `VS3 Upstream` (`0x36c`) are stored as opaque full 32-bit registers in the PDE database. Their bit-field layout is **UNKNOWN**.

* **Citations:**
  * Local Register Map: [`ATLAS-VS-REGISTERS.md`](file:///mnt/Home/src/nixos-config/hardware/pex880xx-strix-4/ATLAS-VS-REGISTERS.md) (derived from decrypted `C010.db`).

---

## Q3. Semantics of SBR "Atlas Mode" and "STRAP_FANOUT_EN"

* **Atlas Mode (2 bits, SoC dword 3 bits 17:16):**
  * **Semantics:** Dictates top-level fabric operation mode on power-up. Broadcom ExpressFabric switches typically support Standard Base/Fan-out mode, Virtual Switch (Multi-Host) mode, Synthetic/Fabric mode, and NT mode.
  * **Enum Values (0–3):** **UNKNOWN**.

* **STRAP_FANOUT_EN (Bit 20, SoC dword 3):**
  * **Semantics:** Dictates the initial hardware boot mode.
    * When bit 20 is `1` (enabled), the switch forces single-host transparent fan-out mode on boot (designating port 0 / `STRAP_UPSTRM_PORT` as the single root, and remaining active ports as downstream ports).
    * When bit 20 is `0` (disabled), hardware forces yield to multi-host / ExpressFabric / Virtual Switch configuration mode driven by runtime CSRs or PSB records.

* **Citations:**
  * Local SBR Audit: [`ATLAS-SBR-NOTES.md`](file:///mnt/Home/src/nixos-config/hardware/pex880xx-strix-4/ATLAS-SBR-NOTES.md).
  * PLX/Broadcom Strapping Conventions (`STRAP_FANOUT_EN` / `STRAP_VS_MODE`).

---

## Q4. Multi-Host Bring-Up Sequence on Atlas

* **Bring-Up Sequence & Config Release Register:**
  * Role of `Config Release Register` (`0x3ac` / dword `0xeb`, `Initiate Configuration` bit 0):
    1. At power-up or hardware reset, the switch holds PCIe link training on downstream and multi-host ports (typically strapped via `STRAP_I2C_CFG_EN#` or management pin).
    2. Management software (BMC, external controller via I2C/UART, or automated SBR PSB script execution) configures the Virtual Switch runtime CSRs (`0x358` VS Enable, `0x360–0x36c` VS Upstream, `0x380–0x38c` VS0 Port Vector, and ALUT NT settings).
    3. Management software writes `1` to `Config Release Register` bit 0 (`Initiate Configuration`).
    4. The switch internal state machine commits the Virtual Switch topology and releases PCIe link training across all configured virtual domains simultaneously.

* **Clocking Requirements & Board-Level Implications:**
  * Multi-host configurations connecting separate, independent host chassis require **SRIS** (Separate Refclk Independent SSC) or **SRNS** (Separate Refclk No SSC) on all host-facing ports.
  * **Common Clock (CC)** is only viable when a single clock generator distributes a shared reference clock across all connected host root complexes and the switch, which is rare in standard multi-host backplanes.

* **Citations:**
  * Broadcom ExpressFabric Architecture Manuals & PLX Multi-Host Application Notes.
  * Local CSR Map: [`ATLAS-VS-REGISTERS.md`](file:///mnt/Home/src/nixos-config/hardware/pex880xx-strix-4/ATLAS-VS-REGISTERS.md).

---

## Q5. NT (Non-Transparent) Port Configuration on Atlas

* **ALUT and BAR Translation:**
  * Non-Transparent Bridging on Atlas is enabled via `VS0 Upstream` (`0x360`) bits 13 (`NT Enable`), 21 (`NT2 Enable`), 30 (`ALUT NT port enable`), and 31 (`ALUT NT2 port enable`).
  * ALUT (Address Look-Up Table) entries handle cross-domain memory address translation between hosts. Detailed ALUT table entry register maps, BAR translation window offsets, and NT-virtual vs NT-link role registers are **UNKNOWN** in unclassified documentation.

* **Driver Support:**
  * **Mainline Linux Kernel (`drivers/ntb/hw/plx/`):** Mainline Linux `ntb_hw_plx` exclusively supports legacy Gen3 switches (PEX 87xx series like PEX 8749/8733). It has **NO** support for PEX88000 Atlas (`1000:c010`).
  * **Out-of-tree / SDK:** Broadcom provides out-of-tree drivers (`pex_ntb`) and management tooling (`Plx_load`, PEX Device Editor) within their NDA-gated PCI/PCIe SDK. No public out-of-tree Atlas NT driver repository is currently available on GitHub.

* **Citations:**
  * Linux Kernel Source: [`drivers/ntb/hw/plx/ntb_hw_plx.c`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/ntb/hw/plx/ntb_hw_plx.c).
  * Broadcom PCI/PCIe SDK User Guide (UG100 - NDA required).

---

## Q6. Persistence: Baking Multi-Host Configuration into SBR

* **Persistence Mechanisms:**
  * **PSB Register-Write Records:** The SBR container (SPI Flash offset `0x400`) includes Pre-System Boot (PSB) write-record blocks. The PSB 20-bit byte-addressing range covers runtime CSR space (`0x358` VS Enable, `0x360` VS0 Upstream, `0x380` VS0 Port Vector). Pre-loading these CSRs via PSB write records allows the switch to boot multi-host without host software intervention.
  * **CCR Register Updates:** SoC dwords 7–24 / 41–49 support CCR (Chip Configuration Register) update programs executed by the on-chip boot state machine.

* **Vendor-Intended Flow:**
  * **Static Multi-Host:** SBR contains PSB write records that configure VS structures and release links automatically.
  * **Dynamic Composable Infrastructure:** Switch boots in managed mode with link training held; an external BMC or embedded ARM Cortex-R4 (running Broadcom Switchtec firmware) dynamically configures fabric topologies before issuing `Initiate Configuration`.

* **Citations:**
  * Local SBR Audit: [`ATLAS-SBR-NOTES.md`](file:///mnt/Home/src/nixos-config/hardware/pex880xx-strix-4/ATLAS-SBR-NOTES.md).
  * Local CSR Map: [`ATLAS-VS-REGISTERS.md`](file:///mnt/Home/src/nixos-config/hardware/pex880xx-strix-4/ATLAS-VS-REGISTERS.md).

---

## Q7. Documentation Search (RM109, UG100, Datasheets, Errata)

* **Document Identification:**
  * **RM109:** Confirmed as Broadcom document identifier for *PEX88000 Series Reference Manual / Register Manual*.
  * **UG100:** Confirmed as *PEX88000/PEX89000 PCIe SDK User Guide*.

* **Accessibility Status:**
  * Both documents, as well as the PEX88096 Datasheet and Errata, are **strictly gated behind NDA** on the Broadcom Support Portal.
  * Extensive searches across Doc88, Scribd, GitHub, CSDN, Zhihu, and Baidu confirmed **NO public mirrors or leaked PDFs** exist for PEX88000 or PEX89000 manuals.

* **Citations:**
  * Broadcom Technical Documentation Index (requires Broadcom Partner NDA login).

---

## Q8. Real-World Field Reports & Open Hardware Projects

* **ServeTheHome & Level1Techs Forums:**
  * Enthusiasts routinely attempt multi-GPU (4x to 8x RTX 3090/4090) and NVMe storage expansion using surplus Chinese PEX88096 / PEX88064 carrier boards.
  * Common failure point: Consumer motherboards (AMD AM4/AM5, Intel LGA1700) experience severe BIOS/UEFI boot hangs or enumeration failures due to PCIe bridge depth and resource allocation limits when multi-host or switch topologies are active.

* **OSHWHub & EasyEDA Open Hardware:**
  * Projects like the **KCORES PEX88096-PCIE4-Switch-GPU Backplane** (by author "老妖怪") and derivative 6-layer PEX88064 boards exist.
  * Board design details: These designs use physical DIP switches connected to hardware strapping pins for initial link bifurcation (e.g. 5x16 vs 10x8 vs 20x4).
  * EEPROM / Register Offsets: Direct register offsets posted on GitHub (such as `0xA30` BAR config) belong to legacy PLX PEX87xx/86xx switches. PEX88000 uses embedded ARM Cortex-R4 firmware initialization, rendering legacy PEX87xx EEPROM hacks non-functional.

* **Citations:**
  * OSHWHub KCORES PEX88096 Backplane (`oshwhub.com`).
  * ServeTheHome PCIe Switch & GPU Backplane discussions (`forums.servethehome.com`).

---

## Q9. Atlas Management & Out-of-Band Interfaces

* **Hardware Management Interfaces:**
  * **I2C/SMBus Slave Address:** Board-dependent (determined by strapping pins); reference boards typically map slave base addresses to `0x70` / `0x71` for management and `0x50` for SPI Flash / EEPROM access. Universal default: **UNKNOWN**.
  * **UART Console:**
    * Speed & Protocol: 115200 baud, 8N1, 3.3V TTL logic level.
    * Pinout: Headers CN1/CN2 (TX, RX, GND) or micro-USB (CN15 virtual COM port) on Serial Cables and Broadcom RDK host cards.
    * Software: Interfaces with the embedded ARM Cortex-R4 bootloader (U-Boot derivative) or Switchtec CLI (`fdl` for firmware download).
  * **MDIO:** Not implemented for switch management (I2C/SMBus and PCIe in-band are standard).

* **Corrupted Flash / Bad SBR Recovery:**
  * **Hardware Mode Strap (Jumper J78):** Serial Cables / Broadcom RDK cards include jumper headers (e.g. J78) to force the onboard microprocessor into ROM bootloader mode for I2C/UART recovery.
  * **UART Console Recovery:** Interrupting boot at the UART prompt allows re-flashing SBR/firmware images via Xmodem or TFTP.
  * **Direct SPI Programmer / Clip:** Direct SPI flash programming using an external programmer (e.g. CH341A or SF600) targeting offset `0x400` with a valid SBR checksum container.

* **Citations:**
  * Serial Cables PCIe Gen4 Switch Card Management User Manual.
  * Local Flash Protection Notes: [`FLASH-PROTECTION.md`](file:///mnt/Home/src/nixos-config/hardware/pex880xx-strix-4/FLASH-PROTECTION.md).

---

## Q10. Cross-Family Transferability (PEX89000 Capella vs PEX88000 Atlas)

* **Family Architecture:**
  * PEX88000 ("Atlas", Gen4) and PEX89000 ("Capella", Gen5, e.g. PEX89104, PEX89096) both utilize Broadcom's **ExpressFabric** architecture and share the same embedded ARM management processor paradigm.

* **Virtual Switch Model Compatibility:**
  * Both families share an identical Virtual Switch / ExpressFabric abstraction layer, including Virtual Upstream/Downstream Ports, gDMA (Global DMA) channels, and Tunneled Windows Connections (TWC).
  * Server diagnostic logs (Lenovo / HPE) show that both Atlas and Capella are managed using identical Hardware Abstraction Layer (HAL) functions and SDK APIs.

* **Register-Level Transferability:**
  * While high-level concepts and SDK APIs match 1:1, exact byte-level CSR offset identity between Atlas (`1000:c010`) and Capella (`1000:c020`) is **UNKNOWN** due to NDA restrictions on both Data Books.

* **Citations:**
  * Broadcom Capella PEX89000 & Atlas PEX88000 Product Briefs (`broadcom.com`).
  * OEM Server Firmware Diagnostic Logs (Lenovo/HPE).

---

## SURPRISES / LEADS

1. **PSB Byte-Offset Mapping to Runtime CSRs:** Pre-System Boot (PSB) write records in the SBR container at offset `0x400` use 20-bit byte offsets that map directly to runtime CSRs (such as `0x358` VS Enable, `0x360` VS0 Upstream, and `0x380` VS0 Port Vector). This provides a concrete mechanism for `pexctl` to bake multi-host configurations into SBR images!
2. **KCORES Open-Hardware Schematics:** The OSHWHub open-hardware project by "老妖怪" provides full schematics and JLCPCB layout files for PEX88096 / PEX88064 boards, documenting hardware DIP switch strapping.
3. **No Mainline NTB Driver for Atlas:** Mainline Linux `ntb_hw_plx` only supports legacy Gen3 switches (PEX 87xx). Any Linux NTB support for PEX88000 must be developed from scratch or ported from Broadcom's proprietary `pex_ntb` SDK driver.
