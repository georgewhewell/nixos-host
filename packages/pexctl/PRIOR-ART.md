# Prior art and field reports

This survey was performed on 2026-07-25. The Atlas/PEX88000 ecosystem is
sparse, fragmented, and frequently mixed together with the different
PEX8600/PEX8700 serial-EEPROM format. Sources are classified below so that a
useful analogy is not mistaken for evidence about PEX88000 SBR.

## Directly relevant

### mithro/plxtools

[`mithro/plxtools`](https://github.com/mithro/plxtools) is the closest public
project found. It is an Apache-2.0 Python CLI whose stated long-term goals
include lane reconfiguration, EEPROM-backed configuration, and out-of-band
recovery.

At commit
[`447296312012`](https://github.com/mithro/plxtools/tree/447296312012251e83437cac6ffc1a1450cc6aee):

- PEX880xx devices can be discovered as Broadcom vendor `0x1000`;
- its Serial Cables ATLAS HOST CARD backend can read registers, port status,
  environmental data, I2C devices, and flash through the card's text console;
- the PEX880xx definition explicitly marks EEPROM configuration as `TBD`;
- its EEPROM decoder implements the older `0x5a` register-write stream, not
  the Atlas indexed SBR format;
- it does not parse or mutate Atlas SBR, and it does not implement the
  recovery-gated in-band erase/program path used by `pexctl`.

The projects are complementary. `plxtools` has the beginning of an
out-of-band management-card backend and a broad device database; `pexctl` has
the lossless Atlas SBR model, proven PlxSvc/manual-SPI transport, exact flash
geometry, candidate construction, and guarded writer.

### Public Broadcom SDK source mirrors

[`xiallc/broadcom_pci_pcie_sdk`](https://github.com/xiallc/broadcom_pci_pcie_sdk)
and [`d4ddi0/PlxSdx`](https://github.com/d4ddi0/PlxSdx) mirror the Linux
PlxSvc/PlxApi portions of older Broadcom SDK releases; the latter carries
newer-kernel build patches. They are useful ABI and driver references, but
they are not independent configuration tools and do not provide an open
Atlas SBR editor.

`pexctl` interoperates with the installed PlxSvc ioctl ABI without linking the
SDK userspace library. The independently implemented ABI boundary and the
specific source provenance remain documented in `THIRD_PARTY-NOTICES.md`.

### Open PEX88096 hardware and SBR images

The GPL-3.0
[`PEX88096-PCIE4-Switch-GPU baseboard`](https://oshwhub.com/eda_nrhnxjzuv/pex88096-pcie4-switch-gpu-basepl)
project publishes hardware design material and configured PEX88096 SBR
attachments. Its notes directly corroborate several Atlas facts:

- stations map consecutive groups of 16 lanes;
- an external 1.8 V SPI flash supplies SBR;
- `MODE_SEL0` selects the primary or CS0 flash and `MODE_SEL1` controls SBR
  loading;
- fallback strap mode exposes stations as four x4 ports when valid SBR is not
  loaded;
- SDK-format SBR begins at offset `0x400` in a programmer-ready SPI image;
- x16, x8, x4, x2, and x1 fan-out configurations are possible in firmware.

Those published SBRs are valuable as a future external validation corpus.
They must not be silently copied into this MIT-licensed package: their
license, board clocking, upstream-port selection, and other settings must be
kept explicit.

### PEX880xx modification reports

A [Level1Techs PEX880xx discussion](https://forum.level1techs.com/t/a-neverending-story-pcie-3-0-4-0-5-0-6-0-sci-fi-bifurcation-adapters-switches-hbas-cables-nvme-backplanes-risers-extensions-the-good-the-bad-the-ugly-will-there-be-a-final-solution/171428?page=48)
contains a report of a PEX88048 B0 being changed to an asymmetric
`x8+x8` plus `x4+x4+x4+x4` layout. The reported method was to dump multiple
SPI images with PlxCm, compare them, identify the changed fields, and handle
the checksum. No reusable source or complete format description was
published. It is useful independent support for the differential method, not
a substitute for a verified implementation.

The same thread records firmware/layout failures that present as a visible
switch with no downstream devices. A separate
[PEX88048 field report](https://forum.level1techs.com/t/generic-pex88048-cards-may-ship-with-misconfigured-eeprom-gen1-x4-upstream/251129)
shows configuration limiting a Gen4 part to Gen1 x4. These reports reinforce
the need for `pexctl` to inspect maximum configured widths and speeds in
addition to current link state.

## Earlier-generation work

Eli Billauer's
[`setpci` EEPROM article](https://billauer.se/blog/2015/10/linux-plx-avago-pcie-switch-eeprom/)
documents in-band reads and writes for a PEX8606. It describes the older
format:

```text
5a 00 <payload-length-le16> (<register-address-le16> <value-le32>)*
```

That is not the PEX88000 indexed SBR format. Its recovery warning does apply
in principle: a bad nonvolatile configuration can stop the switch from
enumerating and thereby remove the same in-band path needed to repair it. The
article recommends an independent I2C path for that case.

An older
[PEX8749 lane-layout post](https://forum.level1techs.com/t/pcie-switch-oculink-nvme-and-sata/216488/14)
lists x16, x8+x8, x8+x4+x4, and x4+x4+x4+x4 encodings in that part's port
configuration register. It is helpful terminology, but its three-bit
station-wide register encoding must not be applied to Atlas quarter codes.

## Adjacent design reference

[`Microsemi/switchtec-user`](https://github.com/Microsemi/switchtec-user) is
an MIT-licensed CLI and library for a different vendor's PCIe switches. It is
not usable on Broadcom PEX parts, but its mature architecture is a good model:
one device API over PCIe, I2C, and UART backends; status and event inspection;
firmware readback and validation; and a narrow kernel/userspace boundary.

## Sources deliberately rejected

Search results contain confident but incorrect vendor conflation. For
example, an AIChipLink article claims that PEX88096 runs Microchip Switchtec
firmware and can be queried with the `switchtec` CLI. Broadcom Atlas and
Microchip Switchtec are different products and management protocols. That
article is not used as evidence.

Forum claims that all PEX880xx configuration is encrypted also conflict with
the plaintext, structurally valid SBR read from this board and with the
configured SBRs published by the open-hardware project. Field reports are
retained as leads, but live bytes, independently reproduced transports, and
vendor or primary project material take precedence.

## Consequences for pexctl

The survey did not find another public tool that parses, mutates, validates,
and safely programs Atlas PEX88000 SBR through the host PCIe path. The
following work should nevertheless be shared or aligned where practical:

1. keep the SBR model independent of transport;
2. add a backend abstraction before adding more live-device operations;
3. support a real out-of-band backend, with the Serial Cables console and a
   direct SPI programmer as candidates;
4. add machine-readable JSON for inspection, diffs, manifests, and topology;
5. validate additional layouts only against licensed reference images and
   live hardware, never by importing older-generation encodings;
6. keep immutable captures and exact recovery prerequisites as first-class
   CLI concepts.
