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

# 3. Write (root; reboot to apply). Accepts an option name or a number.
sudo bios-setup-var set 'Enable Port Bifurcation' Enable --dry-run
sudo bios-setup-var set 'Enable Port Bifurcation' Enable
```

## Safety model

- `set` reads the live variable and refuses unless the target offset currently
  holds a value the question actually allows — the machine-specific check that
  the map's offset is right for the running firmware. A mismatch aborts instead
  of writing blind.
- The full variable is backed up to `/var/tmp/<var>.<oldvalue>.bak` before any
  write; only the target bytes change; the result is read back and verified.
- A question may exist in several platform varstores (e.g. `AmdSetupSHP` vs
  `AmdSetupSTP`). `get`/`set` auto-pick the one whose variable is live and holds
  a legal value; `--varstore NAME` forces the choice.

## Caveats

- The map is firmware-specific: rebuild it after a BIOS update.
- No PCR/attestation — this changes NVRAM the same way the BIOS menu would.
  Some settings only take effect after a full power cycle, not a warm reboot.
- Extraction backends are `uefiextract` (UEFITool) and `ifrextractor-rs`.
