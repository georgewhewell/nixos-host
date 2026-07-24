# Post-reboot baseline: 2026-07-24T21:01:00Z

This capture began immediately after Strix-4 rebooted at
`2026-07-24T21:00:47Z`. It contains ordinary Linux PCI and sysfs reads only.
`PlxSvc` was not loaded, and no PLX SDK register or SPI access was performed.

## Boot identity

- Boot ID: `41151440-98bc-4c6c-b896-bcaff023e1f8`
- System profile:
  `/nix/store/26c7f3ibbbl142jbxlqr04nphbkvlp04-nixos-system-strix-4-26.11.20260718.61b7c44`
- Kernel: `7.2.0-rc2`
- Previous-boot journal: unavailable
- Pstore crash record: none

## Contents

- `host/`: boot, DMI, kernel log, module, IOMMU, and NVMe state.
- `pci/lspci-Dnn.txt`: full enumerated PCI inventory.
- `pci/lspci-tree.txt`: complete PCI hierarchy.
- `pci/*-lspci-vvxxxx.txt`: decoded and raw extended configuration space.
- `pci/config-space/`: 4 KiB binary PCI configuration-space images.
- `pci/sysfs/`: identity, resources, link speed/width, driver, and IOMMU data.

The capture includes the host root port `0000:00:03.1` and all 21 devices in
the PEX bus range `c4` through `d5`.

## Important topology facts

- AMD root port `0000:00:03.1`: Gen4 x4 active, Gen4 x8 maximum.
- PEX upstream `0000:c4:00.0`: Gen4 x4 active, Gen4 x16 maximum.
- BlueField branch port `0000:c7:10.0`: Gen4 x16 active.
- NVMe branch port `0000:ce:00.0`: Gen4 x4 active.
- Empty sibling port `0000:ce:10.0`: link down.
- NVMe `0000:cf:00.0`: Gen4 x4 active and live.

No full SPI image exists yet. Do not treat the earlier 4 KiB comparison
checksum as firmware backup.
