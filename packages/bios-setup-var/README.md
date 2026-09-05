# bios-setup-var

Read and write opaque AMI/AMD BIOS **Setup** EFI variables from Linux, by name.

BIOS-menu toggles (PCIe lane bifurcation, above-4G decode, SR-IOV, ...) are
stored as raw bytes at fixed offsets inside variables like `AmdSetupSHP`. The
offset→meaning map exists only in the firmware's IFR. This tool extracts that
map from a BIOS dump once, then uses it to get/set the live values — turning
BIOS-only settings into scriptable ones.

## Use

```sh
# 1. Build the question map from a dump of THIS machine's BIOS (once per
#    firmware version). Needs the dump, not the running flash.
bios-setup-var build-db WRX90WS_12.09.ROM -o /var/lib/bios-setup-var/db.json

# 2. Explore and read (safe, read-only).
bios-setup-var list bifurcation
sudo bios-setup-var get 'Enable Port Bifurcation'

# Read an exact variable/offset even when IFR string extraction is incomplete.
sudo bios-setup-var raw-get AmdSetup 0xfd

# Snapshot every readable EFI variable without modifying NVRAM. The output is
# created atomically and an existing directory is never replaced.
sudo bios-setup-var snapshot /var/lib/bios-setup-var/snapshots/manual-1

# Show exactly which variables and payload offsets changed between boots.
bios-setup-var snapshot-diff snapshots/boot-1 snapshots/boot-2

# 3. Write (root; reboot to apply). Accepts an option name or a number.
sudo bios-setup-var set 'Enable Port Bifurcation' Enable --dry-run
sudo bios-setup-var set 'Enable Port Bifurcation' Enable

# Raw writes require the expected live value as a compare-and-swap guard.
sudo bios-setup-var raw-set AmdSetup 0xfd 0 --expect 1 --dry-run
sudo bios-setup-var raw-set AmdSetup 0xfd 0 --expect 1
```

## Safety model

- `snapshot`, `list`, `get`, and `raw-get` are read-only. A snapshot contains
  the exact efivarfs files (including their four-byte attribute headers), a
  manifest with separate whole-file and payload hashes, boot/firmware metadata,
  and decoded questions when `--db` names an existing IFR database. Snapshot
  directories are mode `0700`; files are mode `0600`.

- `set` reads the live variable and refuses unless the target offset currently
  holds a value the question actually allows — the machine-specific check that
  the map's offset is right for the running firmware. A mismatch aborts instead
  of writing blind.
- The full variable is content-addressed and backed up under
  `/var/lib/bios-setup-var/backups` before any write; only the target bytes
  change; the result is read back and verified. `--backup-dir` can override
  the persistent location.
- A question may exist in several platform varstores (e.g. `AmdSetupSHP` vs
  `AmdSetupSTP`). `get`/`set` auto-pick the one whose variable is live and holds
  a legal value; `--varstore NAME` forces the choice.
- `raw-set` is deliberately lower-level and therefore stricter: the caller
  must supply `--expect CURRENT`. A changed or mistaken byte aborts the write.

## Confirmed FAEX9 1.04 locations

The following payload offsets were established by changing one Setup field at
a time on strix-2 and diffing complete efivarfs snapshots before and after.
They are evidence for **FAEX9 BIOS 1.04 only**, not a portable firmware API.

| Variable | Payload offset | Width | Meaning observed |
|---|---:|---:|---|
| `AmdSetup` | `0xfc` | 1 | iGPU mode: `0` Auto, `2` UMA specified |
| `AmdSetup` | `0xfd` | 1 | UMA frame buffer: confirmed `0` 512 MiB and `1` 64 GiB; other encodings not yet established |
| `NetworkStackVar` | `0x5` | 1 | Media-detect count (`1..50`) |
| `FixedBootPriorities` | `0xf` | 1 | Boot category byte; changed `2` USB → `3` Network |
| `FixedBootPriorities` | `0x13` | 1 | Boot category byte; changed `3` Network → `2` USB |

For example, this verifies the current 512 MiB dedicated UMA reservation
without relying on the incomplete FAEX9 IFR strings:

```sh
sudo bios-setup-var raw-get AmdSetup 0xfd
# ... @ +0xfd width 1: 0 (0x0)
```

### FAEX9 1.04 PCI settings verified by a live read

Direct extraction of the English `Setup` form package maps **PCI Hot-Plug →
PCI Buses Padding** to `Setup-ec87d643-eba4-4bb5-a1e5-3f3e36b20da9` payload
offset `0x99`, width 1. Its legal encodings are `0=Disabled` and `1..5`; the
firmware default is `1`. A complete post-save snapshot from strix-2 on
2026-08-15 confirmed the live value is `5` at this offset:

```sh
sudo bios-setup-var raw-get Setup 0x99
# result: 5 (0x5)
```

The same snapshot confirmed the adjacent hot-plug resource paddings and the
PCIe link-training controls: five retries, a 1000 microsecond polling timeout,
and unpopulated links kept on. The package ships these `Setup`-form mappings
(including Above 4G Decoding, ReBAR, SR-IOV, and Auto Power On) as
`share/bios-setup-var/faex9-1.04-known.json`. It is deliberately curated: the
full firmware contains IFR copies paired with unrelated HII strings, so a
larger database is not automatically more trustworthy.

## Caveats

- The map is firmware-specific: rebuild it after a BIOS update.
- `build-db` puts scratch data in `.work` beside its output (or the explicit
  `--work-dir`) and removes each extraction tree when finished.
- No PCR/attestation — this changes NVRAM the same way the BIOS menu would.
  Some settings only take effect after a full power cycle, not a warm reboot.
- Extraction backends are `uefiextract` (UEFITool) and `ifrextractor-rs`.
