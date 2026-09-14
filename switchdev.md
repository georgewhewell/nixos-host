# MikroTik 25G LAN + ConnectX-4 Switchdev — incident write-up

Why the LAN port kept failing to come up on reboot, what was actually
broken, and how we made the boot reliable and faster along the way.

## The setup

- Router: AMD board with ConnectX-4 Lx dual-port 25G NIC.
  - PF0 (PCI `0000:01:00.0`) → WAN, MAC `50:6b:4b:03:04:ca`, `enp1s0f0np0`
  - PF1 (PCI `0000:01:00.1`) → LAN, MAC `50:6b:4b:03:04:cb`, `enp1s0f1np1`
- LAN is plugged into MikroTik CRS510 (`mikrotik-crs510.lan.satanic.link`),
  port `sfp28-1`. MikroTik defaults every sfp28 port to
  `auto-negotiation=yes, fec-mode=auto`.
- The WAN PF is flipped to `devlink eswitch mode=switchdev` at boot for
  hardware TC offload. The LAN PF stays in legacy mode because switchdev
  is incompatible with the host's Linux bridge.

## The symptom

After every router reboot the 25G LAN port came up "wrong":

- Sometimes the netdev was `eth1` instead of `enp1s0f1np1`, so the
  `[Match] Name=enp1s0f1np1` in the .network file matched nothing and
  the port was never enslaved to `br0.lan`.
- Sometimes the rename worked but the link stayed `NO-CARRIER` with
  `ethtool` reporting "No partner detected during force mode".
- Recovery was always a manual sequence on the router:

  ```sh
  sudo ip link set enp1s0f1np1 down
  sudo ethtool -s enp1s0f1np1 speed 25000 autoneg off
  sudo ethtool --set-fec enp1s0f1np1 encoding off
  sudo ip link set enp1s0f1np1 up
  ```

  …after which the link trained at 25 Gb/s and stayed up indefinitely.

## What we thought it was (and ruled out)

1. **MikroTik forcing a hard-coded mode.** Checked every `sfp28-*` port:
   all are `auto-negotiation=yes, fec-mode=auto`. No hardcoded
   misconfiguration; the switch is doing exactly what modern best
   practice says.
2. **FEC mismatch.** Worth fixing but not the cause. With autoneg on
   both sides the FEC should negotiate; with the router in force mode
   the MikroTik's auto-FEC usually settles on what the partner sends.
3. **`lan-25g-fec.service` not running.** Was a real bug —
   `wantedBy = ["sys-subsystem-net-devices-…device"]` is unreliable
   because `.device` units are managed by udev rather than systemd's
   normal start path. But fixing it didn't stop the link from flapping.
4. **WAN netdev losing its persistent name (`eth0` instead of
   `enp1s0f0np0`).** This was a separate real bug: switchdev destroys
   and recreates the PF0 netdev, and udev's predictable-name rules
   don't re-fire on the recreated netdev. Fixed by matching the
   `.link` file on `Driver=mlx5_core + PermanentMACAddress=…` and
   pinning `linkConfig.Name = enp1s0f0np0`. Real fix, but not the
   cause of the LAN problem either.

## The actual root cause

The eswitch on a ConnectX-4 Lx is a **NIC-wide resource**. Toggling
eswitch mode on PF0 disturbs the link state of PF1 too, even though
PF1's mode isn't being touched. Reading the boot dmesg from a failed
boot:

```
[136.059] mlx5_core 0000:01:00.0: E-Switch: Disable: mode(LEGACY)
[139.188] mlx5_core 0000:01:00.0: E-Switch: MPFS/FDB active
[139.488] mlx5_core 0000:01:00.0: E-Switch: Enable: mode(OFFLOADS)
[139.741] mlx5_core 0000:01:00.0 enp1s0f0np0: Link down       ← WAN, expected
[139.750] mlx5_core 0000:01:00.1 enp1s0f1np1: allmulticast    ← LAN bridge enslave
[140.030] mlx5_core 0000:01:00.1 enp1s0f1np1: Link down       ← LAN disturbed
[142.217] mlx5_core 0000:01:00.0 enp1s0f0np0: Link up         ← WAN recovers
[222.136] mlx5_core 0000:01:00.1 enp1s0f1np1: Link down       ← LAN still flapping
[362.514] mlx5_core 0000:01:00.1 enp1s0f1np1: Link up         ← finally trains
```

The timeline: the LAN port came up early, `systemd-networkd` enslaved
it to `br0.lan`, and then ~3 seconds later the WAN's switchdev flip
ripped the eswitch state out from under both ports. The bridge was
holding a half-trained link; the autoneg state machine on both sides
tried to recover from a disturbed state and stayed unstable for
minutes. Often it never recovered.

Force-mode + FEC=off was reliable as a manual recovery only because it
re-initialises the SerDes from scratch and asks the MikroTik to do a
plain idle-frame lock instead of a stateful autoneg dance.

## The fix

Move the switchdev service into **initrd**, before `systemd-networkd`
in stage 2 ever touches the netdevs:

```nix
boot.initrd.systemd.services.mlx5-switchdev-wan = {
  description = "Enable switchdev mode on ConnectX-4 Lx WAN port";
  wantedBy = [ "initrd.target" ];
  before = [ "initrd-switch-root.target" ];
  after = [ "sys-subsystem-net-devices-enp1s0f0np0.device" ];
  wants = [ "sys-subsystem-net-devices-enp1s0f0np0.device" ];
  serviceConfig = {
    Type = "oneshot";
    RemainAfterExit = true;
    ExecStart = "${pkgs.iproute2}/bin/devlink dev eswitch set pci/0000:01:00.0 mode switchdev";
  };
};
boot.initrd.systemd.storePaths = [ "${pkgs.iproute2}/bin/devlink" ];
```

Why this works: in initrd nothing observes the LAN's carrier state.
No bridge, no networkd, no NAT — the kernel netdev exists but nobody
cares whether it's up. The eswitch flip can disturb both PFs all it
wants; by the time stage 2 starts, the eswitch is settled in
switchdev mode and `systemd-networkd` enslaves a stable port to the
bridge in one quiet step.

`mlx5_core` was already in `boot.initrd.kernelModules`, so the driver
was loading in initrd; we just needed to do the eswitch flip there
too.

Also dropped from `linux.nix`:

- `.link` directives `AutoNegotiation/BitsPerSecond/Duplex` (no longer
  needed — both sides autoneg cleanly now that the eswitch isn't
  rugpulling them)
- `systemd.services.lan-25g-fec` (no FEC dance required)
- Unused fields in `network.nix` for the LAN port
  (`speedMbps, bitsPerSecond, autoNegotiation, fecEncoding`)

## Two pitfalls hit along the way

### `sys-devices-pci…01:00.0.device` never activates in initrd

First version of the initrd service depended on the PCI device unit:

```nix
after = [ "sys-devices-pci0000:00-0000:00:01.1-0000:01:00.0.device" ];
wants = [ "sys-devices-pci0000:00-0000:00:01.1-0000:01:00.0.device" ];
```

The unit never activates because the PCI device isn't `TAG+=systemd`d
in initrd's udev rules. systemd waits for the default 90 s job
timeout, then runs the service anyway. The fix is to depend on the
**netdev unit** (which *is* tagged):

```nix
after = [ "sys-subsystem-net-devices-enp1s0f0np0.device" ];
wants = [ "sys-subsystem-net-devices-enp1s0f0np0.device" ];
```

Switching the dependency cut initrd from **91 s → 45 s**.

### Hardware TC offload was a no-op the whole time

```
$ devlink dev eswitch show pci/0000:01:00.0
pci/0000:01:00.0: mode switchdev …    ← yes
$ tc filter show dev enp1s0f0np0 ingress
                                       ← empty
$ nft list table inet flow-offload
flowtable f {
  hook ingress priority filter
  devices = { "br0.lan", "enp1s0f0np0" }
                                       ← no `flags offload`
}
```

The nftables flowtable in `profiles/router/linux.nix` accelerates
forwarding via the **kernel software flowtable**, not hardware. Real
HW offload would need `flags offload` on the flowtable *and* both PFs
in switchdev — but switchdev on PF1 breaks the host Linux bridge,
which is why it was kept in legacy mode in the first place.

So as it stands, `switchdev` on PF0 buys us nothing performance-wise.
Two reasonable next steps:

1. Remove the switchdev service entirely (lose nothing, simplify
   boot) — or
2. Add `flags offload` to the flowtable and figure out a topology
   that allows HW offload (more work, probably not worth it for a
   home router).

## Performance gains

| | Before | After |
|---|---|---|
| Total boot time | 2 min 44 s | 2 min 5 s |
| Initrd | 91 s | 45 s |
| Switchdev runs at | boot+136 s (stage 2) | boot+17.5 s (initrd) |
| LAN link up at | boot+162 s, then flaps until 362 s+ | boot+~50 s, stable |
| Bridge enslave catches eswitch flip | yes (LAN dies) | no (eswitch settled) |
| Manual recovery via nanokvm required | every reboot | never |

## Remaining slowdowns (future work)

- **Initrd → stage 2 cleanup ~26 s**: `systemd-udevd` takes 26 s to
  drain its queued device events before it can stop. Mitigation:
  trim `boot.initrd.kernelModules` to just `mlx5_core` so initrd's
  udev queue is small.
- **`systemd-networkd-wait-online` ~34 s**: WAN has
  `RequiredFamilyForOnline = both`, so it waits for IPv6 DHCP-PD to
  fully establish. WireGuard interfaces also have no
  `RequiredForOnline=no` so they're treated as required. Mitigation:
  set WAN to `ipv4` only and wg interfaces to `no`.
- **24 s of firmware POST** — that's the BIOS, nothing to do from
  Linux.

## Files touched

- `network.nix` — dropped unused `lan25g` fields (`speedMbps`,
  `bitsPerSecond`, `autoNegotiation`, `fecEncoding`).
- `profiles/router/linux.nix` —
  - WAN `.link` matches on
    `Driver=mlx5_core + PermanentMACAddress` and sets
    `linkConfig.Name = enp1s0f0np0` (survives switchdev rebuild).
  - LAN `.link` no longer pins speed/autoneg/duplex; the FEC service
    is gone.
- `machines/x86/router/default.nix` —
  - `mlx5-switchdev-wan` moved from `systemd.services` to
    `boot.initrd.systemd.services`.
  - `boot.initrd.systemd.storePaths` includes `iproute2/bin/devlink`.
  - `ethtool-enp1s0f0np0` no longer orders after the (non-existent
    in stage 2) `mlx5-switchdev-wan.service`.
