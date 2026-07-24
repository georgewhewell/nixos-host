# Acquisition commands

The PEX switch was selected as PlxCm device `1D`, PCI address
`0000:c4:00.0`, chip `C010`, revision `B0`.

```text
dev 1D
ver
portinfo
spisave /tmp/pex88096-current-sbr.bin /o 400 /s A68 /cs 0 /mmr /nr
spisave /tmp/pex88096-current-sbr-full.bin /o 400 /s B50 /cs 0 /mmr /nr
q
```

Relevant monitor output:

```text
PLX Console Monitor (64-bit), v8.23 [Jul 24 2026]
PLX API   : v8.23
PLX driver: v8.23 (PlxSvc)
Port Type   : 05 (Upstream port)
Port Number : 00
PCIe Link   : G4x4 / G4x16
Put CPU in reset........... DISABLED
Flash address range........ 000400h -> 000E67h
Write data to file......... Ok (/tmp/pex88096-current-sbr.bin)
-- Complete (0.01 sec  2.6 KB/s) --

Flash address range........ 000400h -> 000F4Fh
Write data to file......... Ok (/tmp/pex88096-current-sbr-full.bin)
```

The `/mmr` option selects the SDK's memory-mapped read path. The `/nr` option
prevents an embedded-CPU reset. `spisave` performs a read.

The second size comes from the live SBR index. The first `0xa68`-byte read is
a truncated prefix retained as evidence; the `0xb50`-byte read is complete.
