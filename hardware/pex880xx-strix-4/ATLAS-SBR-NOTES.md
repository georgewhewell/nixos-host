# Strix-4 PEX88096 SBR findings

This is the recovery-oriented record of the Atlas configuration work. Binary
captures remain under `captures/`; this file records the interpretation so it
is not lost with a tool installation.

## Current board

- PCI BDF: `0000:c4:00.0`
- PCI ID: `1000:c010`, revision B0
- SPI CS0: Winbond-compatible JEDEC `EF 60 18`, 16 MiB
- SBR flash offset: `0x400`
- SBR length: `0xb50` (2896 bytes)
- current SBR SHA-256:
  `f4e0bf5d1d01d3f8daccc7c9c792cf0174e509a725379a646c9704c2cd4caae5`
- current station codes: all six stations `[0,0,0,0]` (x16)
- configured upstream port: 0
- configured maximum link speed: Gen4
- raw lane-enable code: 0

Additional named one-bit fields currently set are:

```text
auto_pcie_link_train_enable
gen1_compliance_n
stp_bypass
station_clock_sequencing_enable
hardware_auto_power_save_enable
ses_endpoint_disable
legacy_plx_i2c_target_enable
```

Secure boot, watchdog, fanout, and flash-signature enablement are currently
clear. These fields require an expected-current expert patch and
`--allow-expert-fields` in `pexctl`; none was changed during this work.

## Indexed write blocks

The live PSB block at SBR offset `0x1fc` is 72 bytes and decodes as nine
8-byte register-write records. Each record contains the value followed by a
descriptor with the dword address, byte mask, and broadcast flag:

| Register offset | Stable key | Value | Byte mask | Broadcast |
|---:|---|---:|---:|:---:|
| `0x20c` | `phy_user_test_pattern_0` | `0x06042019` | `0xf` | no |
| `0xbd4` | `gen3_equalization_tx_coefficient` | `0x81c0a805` | `0xf` | yes |
| `0xbd4` | `gen3_equalization_tx_coefficient` | `0xc1c0a805` | `0xf` | yes |
| `0x264` | `lane_margin_control_1` | `0x14403210` | `0xf` | yes |
| `0xbf0` | `port_safety_2` | `0x0000000c` | `0xf` | yes |
| `0x22c` | `phy_station_chicken_bits` | `0x70000800` | `0xf` | yes |
| `0x760` | `tic_station_control` | `0x20400000` | `0xf` | yes |
| `0x72c` | `gen3_framing_error_disable` | `0x000ffc40` | `0xf` | yes |
| `0xd90` | `reserved_0xd90` | `0x0f208014` | `0xf` | yes |

All descriptor reserved bits are zero. The live PSB SHA-256 is
`117f60dbe9d2db64462cfa6d6d29744e2de97529b57d282bf0bcc6f8b6a005cf`.

The live PSB-SerDes block at `0x244` is `0x908` bytes and decodes as 289
address/value AXI-write records. Its SHA-256 is
`7c33d2deb1db900ff1c12f1b03d6efc08f6ee0ccf13b77cc1bd084d577968b80`.
The Broadcom Base RDK independently decodes as four PSB writes and 265
PSB-SerDes writes. `pexctl sbr entries` exposes both blocks in human or JSON
form, while `inspect --json` retains their decoded entries and every raw
dword. These records remain read-only until their individual reset, ordering,
and board constraints are understood.

The packaged direct-device commands were then run against Strix-4:

```console
sudo pexctl device entries --bdf 0000:c4:00.0 --block psb
sudo pexctl device inspect-sbr --bdf 0000:c4:00.0 --json
```

They reproduced the recorded SBR hash, valid checksum, nine named PSB writes,
and 289 PSB-SerDes writes directly through mapped CS0 reads. Of the SerDes
addresses, 287 encode `both` broadcast and two have no applicable broadcast
encoding. The boot ID remained
`758399aa-a216-4733-90ad-eab6141f7c18`, the switch remained visible at
`0000:c4:00.0`, and no hardware write or reset was issued.

## Station-4 candidate

The desired ASUS Hyper M.2 station is station 4:

```json
{
  "schema": "pexctl.atlas-config.v1",
  "stations": [
    {
      "station": 4,
      "layout": "x4x4x4x4"
    }
  ]
}
```

Applying this configuration changes exactly:

```text
SBR 0x0064: 00 -> 49
SBR 0x0065: 00 -> 02
SBR 0x0b4c: 1a -> cf  (checksum)
```

Candidate SBR SHA-256:
`3736c9fc9d67e99152fa834208ec303ccc2ebe0c60c8518777ab44eb9f87c0ea`.

The declarative `apply-config` path reproduces the previously derived
candidate byte-for-byte. The latest double-read plan is in
`captures/2026-07-25T00-05-29Z/`.

On 2026-07-25 at 00:48 UTC, the new generic live command was also exercised:

```console
pexctl device prepare-config \
  --bdf 0000:c4:00.0 \
  --config station4-x4x4x4x4.json \
  --output-dir /tmp/pexctl-config-plan-v1
```

It produced two matching complete-flash reads with SHA-256
`16796f3fa9f0f88276635c60d1e1e2d581393a3eba5f7a03afed9975aa8ab83b`,
the current and candidate SBR hashes recorded above, and these recovery-region
hashes:

```text
current    52dabae4bbeecbb404371e13634d68a565f687cffa74308a67d641edd30ad6bb
candidate  eae37576515486e0e00db49d96e89ef26c9e02b4d34f9db1800b44fd44af4ce1
```

The JSON diff contained one station change and three byte changes. The host
boot ID remained `758399aa-a216-4733-90ad-eab6141f7c18`, the switch remained
visible at `0000:c4:00.0`, and `hardware-written` remained `no`.

## Cross-checks

The 2664-byte Broadcom `Base_RDK96_v0.0.1.0.bin` image distributed with the
SDK has SHA-256
`62c1c8b7990a8e18f808a65a7da2604a9fca9c0796276821c8bd474a0e35129f`
and contains:

```text
station 0  [7,7,7,7]
station 1  [0,0,0,0]
station 2  [1,1,1,1]
station 3  [0,0,0,0]
station 4  [1,1,7,7]
station 5  [1,1,1,1]
```

This establishes x16 code 0, x4 quarter code 1, and disabled-quarter code 7
when combined with the RDK topology. The
[open PEX88096 hardware project](https://oshwhub.com/eda_nrhnxjzuv/pex88096-pcie4-switch-gpu-basepl)
provides an independent all-x16 Device Editor screenshot and a configured-SBR
attachment.

## Recovery boundary

No hardware write has been performed. In-band programming can erase and
verify the preserved first recovery region, but a bad boot configuration can
remove the switch—and therefore the same in-band repair path—from PCIe.
Run `program-sector0` only after an independent CS0 restore method and a cold
power-cycle path have been physically confirmed.
