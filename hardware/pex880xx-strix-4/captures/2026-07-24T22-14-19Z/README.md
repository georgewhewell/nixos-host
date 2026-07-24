# PCI reallocation recovery: 2026-07-24T22:14:19Z

This capture records the first Strix-4 netboot with `pci=realloc=on`. Trex
was deployed first so that its HTTP and NFS netboot service exposed the new
image, then only Strix-4 was rebooted.

No PLX SDK command, PLX kernel module, SPI operation, reset, or register write
was performed during this test.

## Trex deployment

- Live system:
  `/nix/store/zk7hx6kxdkrwcrlxw3cjvrjdqc8bm9wi-nixos-system-trex-26.11pre-git`
- Served Strix-4 artifact:
  `/nix/store/84sawslx9np3jynl6fbpxigyr4mh9n8s-strix-netboot-strix-4`
- Served iPXE file:
  `/nix/store/lanm8xsf64qma8pylmjpcafya3p6s9p8-netboot-strix-4.ipxe`
- The iPXE file fetched over HTTP matches the store file at SHA-256
  `4bfd48d61114dcf09708007dd4d1225967a73e6cfd0c7edf9ecc64778a44c3f8`.
- Both `nginx` and `nfs-server` were active after activation.

While this evidence was being collected, a user-confirmed concurrent
`nixos-rebuild` and ZFS migration workflow running from
`/mnt/Home/src/nixos-config` activated
Trex system
`/nix/store/f1rbp9rlgn9brq944d1c1bgxdqh5aaxb-nixos-system-trex-26.11.20260718.61b7c44`.
The first switch reported status 101, then a direct switch completed at
00:18:12 local time. The later closure still contains the exact Strix-4
netboot artifact above; the served symlink, HTTP file checksum, nginx, and
NFS state remained unchanged. See `trex/post-capture-activation.txt`.

## Strix-4 result

- Previous boot ID: `9cece791-ad7e-44c8-abd6-ccd7152fb59d`
- New boot ID: `758399aa-a216-4733-90ad-eab6141f7c18`
- New system:
  `/nix/store/lqzb84qrmmr7mnd14bha2iv317skjbbf-nixos-system-strix-4-26.11.20260718.61b7c44`
- The live kernel command line contains exactly one `pci=realloc=on`.
- The root filesystem remains the expected netboot `tmpfs`.

PCI resource allocation recovered:

```text
root/PEX window: 0xdc000000-0xdd3fffff
NVMe BAR 0:      0xdd300000-0xdd303fff
NVMe link:       16 GT/s x4
NVMe driver:     nvme
NVMe state:      live
namespace:       nvme0n1, Corsair MP600 CORE XT, 3.6 TiB
```

The boot log contains no `can't assign`, `no space`, `probe failed`, or
`-ENODEV` result. This confirms that the missing one MiB bridge window caused
the earlier NVMe probe failure and that PCI resource reallocation repairs it.

The BlueField-2 endpoint functions also remain present under the PEX switch at
`0000:c8:00.0` and `0000:c8:00.1`.

## Remaining topology issue

Only one NVMe endpoint is visible under the PEX fabric. The ASUS Hyper M.2
carrier contains four drives, but Linux enumerates only the Phison controller
at `0000:cf:00.0`; the other three expected NVMe functions do not appear.
Therefore this test repairs BAR allocation for the visible drive. It does not
enable or prove x4/x4/x4/x4 lane bifurcation for all four carrier positions.

BlueField-2's ARM root complex still sees only its integrated BlueField PCIe
path and no PEX or NVMe device, so it remains an endpoint rather than the root
of this switch fabric.

## Files

- `trex/system.txt`: deployed Trex profile, service state, and served symlinks.
- `trex/served-netboot.ipxe`: iPXE file fetched through Trex's HTTP service.
- `trex/post-capture-activation.txt`: current Trex profile and the concurrent
  activation timeline that followed the Colmena deployment.
- `strix-4/system.txt`: new boot identity, profile, command line, and root FS.
- `strix-4/pci.txt`: full PCI inventory/tree and verbose root, PEX, and NVMe
  records.
- `strix-4/resources.txt`: sysfs resources and bound drivers along the NVMe
  branch.
- `strix-4/storage.txt`: block layout and NVMe controller state.
- `strix-4/dmesg-pci-allocation.txt`: PCI allocation, NVMe, and AER-related
  boot messages.
- `strix-4/config-space/`: 4 KiB PCI configuration snapshots for the root port
  and repaired NVMe branch.
- `bluefield2/system.txt`: BlueField-2 boot identity and its local PCI view.
- `FILE-SIZES` and `SHA256SUMS`: capture integrity metadata.
