# Cluster reboot check: 2026-07-24T21:46:47Z

This capture followed an intentional whole-cluster reboot. No PLX driver or
PlxCm operation had been run in this boot when the capture was taken.

## Strix-4

- Boot ID: `9cece791-ad7e-44c8-abd6-ccd7152fb59d`
- System profile:
  `/nix/store/rs1hnfkhdg82z6q8ivxskdggvbaw9qpx-nixos-system-strix-4-26.11.20260718.61b7c44`
- `PlxSvc` and the fixed PlxCm are available but not loaded or invoked.
- The PEX switch, BlueField functions, and NVMe PCI function enumerate.
- The NVMe PCIe link trained successfully at Gen4 x4.
- The NVMe driver failed with `-ENODEV`; there is no `nvme0`.

The cause is PCI MMIO resource exhaustion, not link training:

```text
pci 0000:cf:00.0: BAR 0 [mem size 0x00004000 64bit]: can't assign; no space
nvme 0000:cf:00.0: error -ENODEV: probe failed
```

The AMD root port's non-prefetchable memory window was one MiB smaller than
in the earlier healthy capture:

```text
healthy: 0xdc000000-0xdd3fffff  config DWORD 0x20 = dd30dc00
current: 0xdc000000-0xdd2fffff  config DWORD 0x20 = dd20dc00
```

The PEX subtree requires the missing `0xdd300000-0xdd3fffff` bridge window
for the NVMe branch. See `strix-4/healthy-vs-current.txt` and
`strix-4/dmesg-pci-allocation.txt`.

## BlueField-2

- Boot ID: `8fd07ae8-7f33-4b9c-89c2-dc5d4e542ffe`
- System profile:
  `/nix/store/2pf7f0bvpm5fy8db1nlzrqawh8cb749k-nixos-system-bluefield2-26.11pre-git`
- Both management networks are reachable.
- Its ARM root complex sees only the integrated BlueField PCI function.
- It sees no PEX switch and no NVMe, confirming it remains an endpoint rather
  than the owner/root of this PEX fabric.

No SPI/MMR reproduction was attempted because the post-reboot NVMe baseline
was already unhealthy.
