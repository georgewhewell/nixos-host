# Acquisition commands

The commands below were run from `/mnt/Home/src/nixos-config`.

## Host and PCI state

```sh
ssh strix-4 '<read-only host command>'
```

The host files contain the exact command as their first line where practical.
PCI configuration-space binaries were read from
`/sys/bus/pci/devices/<BDF>/config` using `sudo dd`.

## PLX monitor

The patched monitor fixes the vendor parser bug that discarded the first
`spisave`/`spiload` argument. It does not change SPI access behavior.

```text
dev 1D
ver
portinfo
pcicap
dp 0 1000
dr 0 1000
```

Visible PEX functions are selected individually for `portinfo`, `pcicap`, and
PCI-register dumps. These commands perform reads.

## SPI consistency test

```text
dev 1D
spirw 0 /cs 0
spirw 4 /cs 0
spisave spi-manual.bin /o 0 /s 1000 /cs 0 /nr
spisave spi-mmr.bin /o 0 /s 1000 /cs 0 /mmr /nr
```

The two 4 KiB results were identical:

```text
be01c00002ba3c1392cb4eadb85b98c9543569eafad85815561dadafc45b1dc3
```

## Full SPI CS0 dump (planned, not executed)

The SDK declares CS0 as 256 sectors of 256 KiB, or 64 MiB. Manual reads do
not support addresses at or above 16 MiB, so the complete dump uses the
documented memory-mapped read path:

The following command was derived from the SDK source, but was not run in
this session because Strix-4 rebooted after the 4 KiB consistency test:

```text
dev 1D
spisave pex880xx-cs0.bin /o 0 /s 4000000 /cs 0 /mmr /nr
q
```

`4000000` is hexadecimal in PlxCm and equals 67,108,864 bytes.
