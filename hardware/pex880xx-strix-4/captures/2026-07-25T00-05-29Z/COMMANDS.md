# Acquisition and validation commands

The tested static binary was:

```text
/nix/store/g7afxwfkcks8k7iwaz51sj03f1d1y3gh-pexctl-static-x86_64-unknown-linux-musl-0.1.0/bin/pexctl
```

It was copied to Strix-4 as `/tmp/pexctl-prepare-test`.

## Serial-only recovery-region read

```console
sudo pexctl device read-flash \
  --bdf 0000:c4:00.0 \
  --offset 0 \
  --size 0x40000 \
  --method serial \
  --output /tmp/pex88096-cs0-sector0-pexctl-serial.bin
```

The serial result was compared with the mapped `pexctl` capture and the
independent PlxCm capture from the prior session. All three matched.

## Prepare station 4

```console
sudo pexctl device prepare-station \
  --bdf 0000:c4:00.0 \
  --station 4 \
  --layout x4x4x4x4 \
  --output-dir /tmp/pexctl-station4-plan-v1
```

Result:

```text
prepared verified station plan in /tmp/pexctl-station4-plan-v1:
station 4 [0, 0, 0, 0] -> [1, 1, 1, 1] (x4+x4+x4+x4)
two complete 16777216-byte flash reads matched; hardware was not written
required write confirmation:
ERASE-PROGRAM-VERIFY:0000:c4:00.0:CS0:SECTOR0
```

## Independent validation

```console
cd /tmp/pexctl-station4-plan-v1
sha256sum current-flash-a.bin current-flash-b.bin \
  current-region.bin current-sbr.bin candidate-region.bin candidate-sbr.bin
cmp current-flash-a.bin current-flash-b.bin
pexctl sbr validate current-sbr.bin
pexctl sbr validate candidate-sbr.bin
pexctl sbr diff current-sbr.bin candidate-sbr.bin
cat /proc/sys/kernel/random/boot_id
```

Both complete reads matched, both SBRs validated, the diff contained only the
two station bytes and checksum, and the boot ID remained
`758399aa-a216-4733-90ad-eab6141f7c18`.

No erase, program, reset, reboot, or topology-changing command was run.
