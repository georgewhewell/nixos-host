# Strix-4 PEX88096 VS/multi-host runtime register map

This note records the Atlas virtual-switch (multi-host), NT, and port-control
registers decoded from the vendor PDE device database
(`Pde/db/pex_device_atlas.db`, the decrypted form of the SDK's `C010.db`),
extracted 2026-07-25 with reflection probes over the vendor Java classes.
It complements [`ATLAS-SBR-NOTES.md`](ATLAS-SBR-NOTES.md): the SBR contains
no multi-host fields, so everything here is runtime CSR territory.

Address facts:

- `ee` is the vendor dword index; `abs = ee * 4` is the byte offset within
  the port-0 CSR page.
- Port CSR pages begin at BAR0 offset `0x800000`
  (`ATLAS_PORT_REGISTERS_MAPPED_OFFSET` in `pexctl`). The port-0 page stride
  is not yet verified on hardware; read-back of the registers below is the
  planned first `pexctl device reg-read` experiment.
- All defaults below are vendor database defaults, not live observations.

## Global configuration registers (port 0)

| abs | Register | Fields |
|---:|---|---|
| `0x300` | Port Configuration 0 | station 0 config `[11:0]`, station 1 config `[27:16]` (12 bits = four 3-bit quarter codes) |
| `0x304` | Port Configuration 1 | stations 2–3, same layout |
| `0x308` | Port Configuration 2 | stations 4–5, same layout |
| `0x30c`–`0x318` | Clock Enable 0–3 | per-port clock enable bits; only port 0 defaults to 1 |
| `0x320` | Stn Lane Enable | station lane 15:0 enable `[15:0]` |
| `0x330` | Stn Software Lane Status | station lane-up status `[15:0]` |
| `0x334` | STN Ref Clock select | vendor-reserved contents |
| `0x340`/`0x344` | Non Volatile Memory Data / Control | serial EEPROM/SBR access |
| `0x34c` | Chip Bring up Control | `Upstream Hot Reset Cntrl` bit 2, `disable SBR load on lvl1` bit 3, `Upstream Port DL Down reset propagation Disable` bit 4 |
| `0x350` | Debug Control | `Cut through Enable` bit 11 (def 1), `Port Reset EEP Load` bit 22, `Switch Mode` bit 30 |

## Management, VS, and NT registers (port 0)

| abs | Register | Fields |
|---:|---|---|
| `0x354` | Management Port Control | `Active Management Port` `[7:0]` def 0, `Active Management Port Enable` bit 8 def 1, `Redundant Management Port` `[23:16]`, `Redundant Management Port Enable` bit 24 |
| `0x358` | VS Enable | `VS0 Enable` bit 0 def 1; `VS1`–`VS3 Enable` bits 1–3 def 0 |
| `0x360` | VS0 Upstream | `VS0 Upstream Port` `[7:0]`, `NT Port` `[12:8]`, `NT Enable` bit 13, `NT2 Port` `[20:16]`, `NT2 Enable` bit 21, `DMA Mode` bit 24, `VC Mode` bit 25, `ALUT NT port enable` bit 30, `ALUT NT2 port enable` bit 31 |
| `0x364` | VS1 Upstream | `VS1 Upstream Port` `[31:0]` (encoding not verified) |
| `0x368` | VS2 Upstream | `VS2 Upstream Port` `[31:0]` (encoding not verified) |
| `0x36c` | VS3 Upstream | `VS3 Upstream Port` `[31:0]` (encoding not verified) |
| `0x380`–`0x38c` | VS0 Port Vector | 98-bit active-port bitmap: ports 31:0, 63:32, 95:64, then 97:96 at `0x38c[1:0]` |
| `0x390`–`0x394` | Reserved | confirmed reserved in the database — **no VS1/VS2 vector registers exist** |
| `0x398`–`0x3a4` | Port Level0 Reset 0–3 | per-port reset bitmap: ports 31:0, 63:32, 95:64, then port 116 bit 0 / port 117 bit 1 at `0x3a4` |
| `0x3a8` | VS PERSTn Status | `VS3-0 PERSTn Pin Value` `[3:0]`, `VS3-0 PERST Ctrl` `[11:8]`, `NT1-0 PERSTn Pin Value` `[17:16]`, `NT1-0 PERSTn Ctrl` `[25:24]` |
| `0x3ac` | Config Release | `Initiate Configuration` bit 0 (probable commit trigger) |
| `0x3f8`–`0x3fc` | On-chip probe (Monitor/InOut) | sample count, trigger, RAM control/data — the marketed PCIe analyzer block |

Address-collision warning: legacy Gen3 PLX driver code (`PlxMH_*`) uses
`0x380 + i*4` as per-VS port vectors and `0x3A0` as a VS reset register.
On Atlas those offsets are VS0's widened vector and the port-95:64 Level0
reset dword respectively. Do not apply Gen3 multi-host driver semantics to
these addresses.

Resolved questions (2026-07-29, vendor SDK source review):

- VS1–VS3 port-vector registers **do not exist** on Atlas: `0x390`+ is
  reserved and VS0's vector is widened to four dwords. VS1–3 membership is
  not expressible in standard mode; partitioning is fabric-mode territory.
  See [`ATLAS-RUNTIME-MODEL.md`](ATLAS-RUNTIME-MODEL.md).
- The `upstream management privilege` bit is bit 31 of the **TIC Chip
  Control Register** at `ee=0x1d9` (byte `0x764`).
- VS1–3 Upstream registers are labeled full-dword in the database; the
  vendor SDK reads every VS upstream register with one code path, so the
  VS0 structured layout (upstream port low byte, NT/NT2/ALUT fields) is the
  expected encoding for VS1–3 as well (unproven on hardware).
- `Physical Layer Command or Status Register` (`ee=0x87`, per station)
  carries `Upstream crosslink enable` bit 5 and `Downstream crosslink
  enable` bit 6, both default 1: the switch auto-resolves cross-linked
  cabling per station.

## Conclusions for configuration

1. Single-host (fan-out) upstream selection is entirely SBR-side:
   `soc.upstream_port` (`STRAP_UPSTRM_PORT`, first SoC dword bits 7:0).
   No per-port role fields need to change with it; all reference images
   (live, Base RDK96, vendor template) hold all-zero `Port Type` and
   `Clocking mode` tables with upstream port 0. Vendor SDK source confirms
   the runtime mirror: in standard mode the upstream port is `0x360[7:0]`.
2. The SBR SoC region (all 104 dwords, audited against the vendor
   `AtlasSBR.db` template) contains no VS, port-vector, or NT fields.
   Multi-host partitioning is not expressible in standard mode: VS1–3 have
   no membership vectors, and fabric-mode ports/management endpoints exist
   only when CCR `0xB0[1:0] = 1` (fabric/synthetic). The decoded runtime
   model, CCR/IDX_AXI access path, and evidence tiers live in
   [`ATLAS-RUNTIME-MODEL.md`](ATLAS-RUNTIME-MODEL.md).
3. Per-VS reset (`VS PERSTn`, `0x3a8`) plus `Initiate Configuration`
   (`0x3ac` bit 0) are the Atlas-labeled domain-reset and commit controls;
   semantics beyond the names are unproven until read on hardware.
4. Vendor template defaults: all station quarter codes `1` (fallback
   x4/x4/x4/x4 without valid SBR, corroborating the open-hardware project
   note), `PCIE_Max_link_speed` 2 (Gen3), `VS0 Enable` 1, upstream port 0.
5. `Port Type` / `Clocking mode` two-bit SBR fields: positions and packing
   vendor-confirmed; the SDK decodes CCR `0x120` port-type value `1` as
   "fabric port" in fabric mode. The SBR table is the same packing and is
   the presumed boot-time copy; values 2–3 and all Clocking-mode values
   remain unknown.
