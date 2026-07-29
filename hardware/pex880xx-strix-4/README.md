# Strix-4 PEX880xx recovery dossier

This directory records the Broadcom/PLX PEX880xx board installed in
`strix-4`. The switch identifies as `1000:c010`, chip `C010`, revision `B0`.

Each operation gets a new UTC timestamp under `captures/`. Captures are
immutable evidence: do not replace an old dump with a newer one.

See [`ATLAS-SBR-NOTES.md`](ATLAS-SBR-NOTES.md) for the decoded format facts,
current hashes, independently cross-checked station encodings, and the exact
station-4 candidate.

See [`FLASH-PROTECTION.md`](FLASH-PROTECTION.md) for the PLX SDK FAQ recovery
guidance, the exact W25Q128JW protection bits and commands, and the fail-closed
write preflight.

See [`ATLAS-VS-REGISTERS.md`](ATLAS-VS-REGISTERS.md) for the decoded
virtual-switch (multi-host), NT, management, and port-control runtime
register map, and for the single-host upstream-port configuration boundary.

## Safety rules

- Capture the current state before and after any configuration change.
- Use only documented read commands while creating a baseline.
- Never run `spiload`, `spierase`, EEPROM writes, register writes, or `reset`
  as part of a capture.
- Always pass `/nr` to `spisave`; this prevents the SDK from resetting the
  switch's embedded CPU.
- Record the exact host, system profile, tool build, command transcript,
  file size, and SHA-256 checksum for every nonvolatile dump.
- Do not assume a successful SPI read is a complete recovery procedure.
  Restoring a PEX board can require an out-of-band interface, board-specific
  strap knowledge, and a known-good power-cycle path.

## Capture sessions

- [`2026-07-24T20-49-20Z`](captures/2026-07-24T20-49-20Z/README.md):
  initial PlxCm and 4 KiB SPI read-consistency test, followed by an
  unexplained host reboot.
- [`2026-07-24T21-01-00Z`](captures/2026-07-24T21-01-00Z/README.md):
  post-reboot Linux PCI, config-space, sysfs, storage, and host baseline.
- [`2026-07-24T21-46-47Z`](captures/2026-07-24T21-46-47Z/README.md):
  cluster-reboot comparison where the NVMe link trained but PCI MMIO
  allocation stopped one MiB short, causing the NVMe probe to fail.
- [`2026-07-24T22-14-19Z`](captures/2026-07-24T22-14-19Z/README.md):
  Trex deployment and Strix-4 netboot with `pci=realloc=on`; the missing
  bridge window and visible NVMe recovered, while only one of the four
  carrier drives remains enumerated.
- [`2026-07-24T22-30-09Z`](captures/2026-07-24T22-30-09Z/README.md):
  live PEX88096 port map, corrected complete SBR backup, and the three-byte
  station-4 candidate for changing the ASUS Hyper M.2 branch from x16 to
  x4/x4/x4/x4.
- [`2026-07-24T23-34-55Z`](captures/2026-07-24T23-34-55Z/README.md):
  verified open `pexctl` PlxSvc/SPI transport, JEDEC and memory-window
  corrections, two matching complete 16 MiB CS0 backups, three matching
  recovery-region reads, and a sector-preserving candidate. Nothing was
  programmed.
- [`2026-07-25T00-05-29Z`](captures/2026-07-25T00-05-29Z/README.md):
  live validation of the recovery-first `prepare-station` workflow, including
  two matching complete flash passes, a serial-only recovery-region
  cross-check, a hashed station-4 plan, and exact candidate reproduction.
  Nothing was programmed.
- [`2026-07-25T08-50-56Z`](captures/2026-07-25T08-50-56Z/README.md):
  read-only W25Q128JW status/protection inspection after adding the fail-closed
  writer preflight. SR1/SR2/SR3 were `00/02/00`, the preflight passed, and the
  live SBR, boot ID, PCI identity, and station-4 recovery plan were unchanged.
