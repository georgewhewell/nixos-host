# Acquisition and validation commands

The tested static binary was:

```text
/nix/store/5y9ch97fwrxpf5sz874sb6sc1ngb6605-pexctl-static-x86_64-unknown-linux-musl-0.1.0/bin/pexctl
```

## Rust PlxSvc SBR read

```console
sudo pexctl device read-sbr \
  --bdf 0000:c4:00.0 \
  --output /tmp/pexctl-sbr-ioctl-20260725.bin
```

Result:

```text
read valid 2896-byte SBR from 0000:c4:00.0 (1000:c010) through PlxSvc
SHA-256 f4e0bf5d1d01d3f8daccc7c9c792cf0174e509a725379a646c9704c2cd4caae5
```

## Recovery-region reads

```console
sudo pexctl device read-flash \
  --bdf 0000:c4:00.0 --offset 0 --size 0x40000 \
  --output /tmp/pex88096-cs0-sector0-a.bin

sudo pexctl device read-flash \
  --bdf 0000:c4:00.0 --offset 0 --size 0x40000 \
  --output /tmp/pex88096-cs0-sector0-b.bin

cmp /tmp/pex88096-cs0-sector0-a.bin \
    /tmp/pex88096-cs0-sector0-b.bin
```

Independent PlxCm read:

```text
dev 1D
spisave /tmp/pex88096-cs0-sector0-plxcm.bin /o 0 /s 40000 /cs 0 /mmr /nr
q
```

All three files have SHA-256:

```text
52dabae4bbeecbb404371e13634d68a565f687cffa74308a67d641edd30ad6bb
```

## SPI identity and complete backups

```console
sudo pexctl device spi-id --bdf 0000:c4:00.0

sudo pexctl device backup-flash \
  --bdf 0000:c4:00.0 \
  --output /tmp/pex88096-cs0-complete-c.bin

sudo pexctl device backup-flash \
  --bdf 0000:c4:00.0 \
  --output /tmp/pex88096-cs0-complete-d.bin

cmp /tmp/pex88096-cs0-complete-c.bin \
    /tmp/pex88096-cs0-complete-d.bin
```

Result:

```text
SPI CS0 JEDEC ID: ef 60 18
size: 16777216 bytes
SHA-256: 16796f3fa9f0f88276635c60d1e1e2d581393a3eba5f7a03afed9975aa8ab83b
```

## Candidate construction

```console
pexctl flash replace-sbr \
  pex88096-cs0-sector0-pexctl-a.bin \
  ../2026-07-24T22-30-09Z/pex88096-station4-x4x4x4x4-candidate.bin \
  --output pex88096-cs0-sector0-station4-x4x4x4x4-candidate.bin

pexctl flash extract-sbr \
  pex88096-cs0-sector0-station4-x4x4x4x4-candidate.bin \
  --output pex88096-station4-x4x4x4x4-from-sector.bin
```

No erase, program, or reset command was run.
