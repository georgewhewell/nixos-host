# Radeon PRO V620 power caps

Strix-2's inventory in `network.nix` configures four reference V620s at
**180 W PPT each** (720 W combined, versus the stock 1000 W). This is an
initial cooling mitigation, not a verified sustainable thermal limit.
Change `strix.v620.powerLimitWatts` to tune the cap within 120–250 W.
The Strix Halo iGPU and its RyzenAdj limits are separate.

`profiles/amd-v620-powercap.nix` adds a small kernel patch derived from
[v620_toolbox at 050d893](https://github.com/blivioniag/v620_toolbox/blob/050d893fa989d606ef91a08d1da17d015f9adf4f/powertuning/patches/v620-powercap-min-120W.patch).
It lowers the driver's minimum PPT limit to 120 W only for PCI `1002:73a1`,
subsystem `1002:0e34`. The firmware default and maximum remain unchanged.
Nix builds the patch into the selected kernel and its initrd module closure;
there is no manually replaced module or additional flake dependency.
The USB4 kernel adapter merges host patches into its upstream `argsOverride`
patch list; an assertion rejects a selected kernel that drops the V620 patch.

The `v620-powercap.service` finds cards by all four PCI identity fields,
sets `power1_cap` in microwatts, and checks readback for every expected card.
It retries enumeration for up to 60 seconds and fails if any card is missing,
unready, outside the allowed range, or rejects the cap. Qwen serving requires
successful verification before starting. A 30-second timer restores caps
that a GPU reset or resume may have returned to their default. Other manual
GPU workloads should also wait for this service. The timer is not an
instantaneous thermal interlock.

Only `power1_cap` is written. Do not substitute writes to `pp_table` or
`pp_features`: the upstream V620 investigation reports SMU hangs with those
interfaces. No VBIOS modifications or extra OverDrive kernel flags are needed.

## Build and verification

Include the new files in the flake's Git source before building:

```sh
nix build .#nixosConfigurations.strix-2.config.system.build.toplevel
python3 -B -m unittest discover -s tests -p test_amd_v620_powercap.py -v
```

Publish/deploy through the usual netboot workflow, then **boot the new
kernel**. Switching a NixOS generation does not replace an already-loaded
amdgpu module; the cap service intentionally fails on a stock 250 W floor.
After boot:

```sh
systemctl start v620-powercap.service
journalctl -b -u v620-powercap.service
journalctl -b -k --grep='V620: allowing PPT'
systemctl status v620-powercap.timer qwen38-serve.service
```

Confirm the four V620 hwmon devices report `power1_cap_min=120000000`,
`power1_cap=180000000`, and the existing maximum (normally `250000000`).
Run a monitored workload and inspect per-card power, junction and memory
temperatures before accepting 180 W for sustained operation. A successful
write/readback proves the requested cap was accepted; it does not prove
that the available airflow is sufficient.

## Telemetry examined on 2026-09-16

VictoriaMetrics recorded all four V620 minimum caps at 250 W. Its last
successful node-exporter sample was **21:22:37 UTC / 23:22:37 Zurich**;
the next scrape failed at approximately 21:23:37 UTC. SSH was subsequently
unavailable on both strix-2's LAN and fabric addresses.

The host recovered at about 21:49 UTC into its previous kernel. A live
read-only check then confirmed all four reference-board PCI identities and
`power1_cap`, `power1_cap_min`, and `power1_cap_max` still at 250 W. The
patched netboot image was built but has not been published or booted.

The available GPU samples over the preceding day showed maxima of only
30–32 °C and 7–10 W per V620. Those samples do **not** establish overheating
as the cause of this outage; a short excursion between one-minute scrapes
cannot be excluded. Hardware acceptance and sustained-load thermal
verification remain pending until the patched kernel is running.
