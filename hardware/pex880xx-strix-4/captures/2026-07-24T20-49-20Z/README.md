# Initial read test: 2026-07-24T20:49:20Z

This session tested the PLX SDK and compared two read paths. It occurred
before any PEX register, EEPROM, SPI, reset, or lane-configuration write.

## Identity

- Host: `strix-4`
- Machine ID: `c0cfaa5cf32f4987b010df298bd8d247`
- Switch PCI ID: `1000:c010`
- Detected chip/revision: `C010 B0`
- Selected management function: `0000:c4:00.0`, upstream port 0
- PLX SDK/API/driver: 8.23
- Capture tool:
  `/nix/store/skbai1c0iaqlgq2pk4lhdxv7h7m66nzk-plxcm-8.23/bin/PlxCm`
- Capture tool SHA-256:
  `5645ae8425b15ea58b1fce7ac015cbe94993a6a2517a7d7f9c213f5adb8158ed`

## Initial observation

The switch upstream link reports Gen4 x4 active and Gen4 x16 capable.
BlueField-2 is visible below PEX port `10`; one NVMe controller is visible
below port `50`. The remaining three M.2 devices are not enumerated.

All commands in this capture are reads. `spisave` is invoked with `/nr`, and
no reset, erase, program, EEPROM write, register write, or PCI rescan is used.

Two temporary 4 KiB CS0 dumps—one manual SPI read and one memory-mapped
read—were byte-for-byte identical. Both had SHA-256:

```text
be01c00002ba3c1392cb4eadb85b98c9543569eafad85815561dadafc45b1dc3
```

The temporary binaries were deleted after comparison and are therefore not
recovery artifacts. Strix-4 rebooted after this completed test. No reboot or
reset command was issued by the capture process, and the next boot had no
previous journal or pstore crash record. No further PLX or SPI operation was
performed in this session.

See [`COMMANDS.md`](COMMANDS.md) for the exact commands. The post-reboot
baseline is in
[`2026-07-24T21-01-00Z`](../2026-07-24T21-01-00Z/README.md).
