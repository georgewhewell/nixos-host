# Strix-4 PEX88096 flash protection and recovery boundary

This note records the vendor material used to gate writes to the switch's
Winbond-compatible `EF 60 18` CS0 flash. It is evidence for refusing a write;
it is not permission to erase or program the board.

## Vendor material reviewed

The following documents were read on 2026-07-25:

- PLX SDK 8.23 `SDK_Standard_Docs/PLX_SDK_General_FAQ.pdf`, especially
  sections 2.7, 2.8, and 2.9;
- Winbond
  [`W25Q128JW Rev. I`](https://www.winbond.com/resource-files/W25Q128JW_RevI%2005262026%20Plus.pdf),
  sections 6, 7, 8.1, 8.2, and the individual block-lock command
  descriptions on pages 54 through 56;
- Broadcom PLX SDK 8.23 `Windows_Api/SpiFlash.c` and `SpiFlash.h`, for the
  Atlas manual-SPI controller transaction sequence.

The PLX FAQ's `5Ah` EEPROM examples and the `0x260`/`0x264` EEPROM controller
registers apply to older PEX8000/PEX8700 devices. They are not the Atlas
PEX88096 SBR format or transport. Its recovery lessons do apply:

- write protection may cause the SDK's write operation to fail because the SDK
  assumes protection has already been disabled;
- a corrupt EEPROM/flash image may make the switch unstable or stop it from
  enumerating, removing the same in-band path needed to repair it;
- an external programmer or an independent I2C path is the preferred recovery
  route.

The FAQ also describes live hot-swap, EEDO-short and similar last-resort
techniques. They are deliberately outside this procedure. This board needs a
verified out-of-band restore path before an in-band block erase is acceptable.

## Exact W25Q128JW state used by pexctl

For the observed `EF 60 18` device, `pexctl device flash-status` issues only
read commands:

| Command | Meaning used |
|---:|---|
| `05h` | Status Register 1: BUSY bit 0, WEL bit 1, BP bits 4:2, TB bit 5, SEC bit 6, SRP bit 7 |
| `35h` | Status Register 2: SRL bit 0, CMP bit 6, suspend bit 7 |
| `15h` | Status Register 3: WPS bit 2 |
| `3Dh + 000000h` | address-zero sector lock; bit 0 is one when locked |

When WPS is zero, BP/TB/SEC/CMP select status-register protection. The writer
requires BP and CMP to be zero. Some other combinations may leave address zero
unprotected, but `pexctl` refuses them instead of inferring that a partially
protected device is safe to modify.

When WPS is one, the individual block/sector locks are active and the global
BP/TB/SEC/CMP map is inactive. The writer reads address zero with `3Dh` and
requires its lock bit to be zero. It does not unlock the sector and it does not
change WPS or any status register.

The writer also refuses a pre-existing BUSY, WEL, or suspended-operation
state. Immediately before every `D8h` erase and `02h` page program, it issues
`06h` and reads Status Register 1 to prove WEL became one. After the operation
finishes, it requires WEL to have returned to zero. A failed WEL assertion
prevents the destructive command from being sent; a WEL bit that remains set
afterward stops all further programming.

## Live observation

The packaged implementation was run read-only on Strix-4 at
`2026-07-25T08-50-56Z`. It reported SR1 `0x00`, SR2 `0x02`, and SR3 `0x00`.
The flash was idle, WEL was clear, BP and CMP were clear, no operation was
suspended, WPS selected the status-register scheme, and QE was the only set
decoded bit. The writer preflight passed.

The boot ID stayed `758399aa-a216-4733-90ad-eab6141f7c18`, PCI identity
remained `1000:c010` revision `0xb0`, the live SBR hash stayed
`f4e0bf5d1d01d3f8daccc7c9c792cf0174e509a725379a646c9704c2cd4caae5`,
and the existing station-4 plan still verified. The raw JSON and command
record are in
[`captures/2026-07-25T08-50-56Z`](captures/2026-07-25T08-50-56Z/README.md).
No Write Enable, status-register write, erase, page program, reset, or reboot
was issued.
