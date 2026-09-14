# CRS812 nix-routeros adoption

This records the completed staged OpenTofu/Terranix control-plane adoption.
The existing
[`machines/routeros/crs812/config.rsc`](machines/routeros/crs812/config.rsc)
remains authoritative for the switch-chip and platform-specific parts of the
CRS812 migration.

## Ownership boundary

The local `nix-routeros` fork models the stable RouterOS API resources that are
safe to import: identity, clock, IP/IPv6 settings, management IP, the single
hardware bridge, MAC-server settings, IPsec defaults, and the switch-wide
L3HW/QoS-offload booleans. Provider 1.99.1 cannot safely import the live IP
service rows or neighbor-discovery singleton on RouterOS 7.24, so phase one
gates those out too. The fork deliberately does not claim QoS profiles,
tx-manager queues, PFC, or other CRS812 switch-chip state. Those remain in
`config.rsc` until the provider has explicit schemas and a production import
has been reviewed.

The adoption and transition renderers keep `vlanFiltering = false`; only the
attended cutover renderer enables it. The live switch is now in that accepted
cutover state with filtering enabled.

The primary map is now confirmed: empty `sfp56-8` is reserved for the ISP, and
the BlueField trunk is `qsfp56-1-1` at 100G CR4/RS-FEC. The review-only target
makes VLAN 100 untagged/PVID 100 on `sfp56-8` and tagged on the BlueField port.
The VLAN row deliberately omits `bridge`, so the RouterOS CPU cannot enter the
ISP broadcast domain. `sfp56-7` is excluded: its 5 m SFP28 DAC is live at 25G
to Rock-5B. No live setting was changed while confirming either port.

The refreshed live bridge inventory contains 34 physical members. Every one
was imported with PVID 1, `frame-types=admit-all`, and ingress filtering
enabled. The original VPP lab VLAN and two physical Ethernet rows are imported
too. Together with the first 11 stable objects, all 48 adopted resources now
produce a zero-change plan.

The backup transit is VLAN 101. The live FDB places both k3 wired MACs behind
CRS812 `sfp56-6`, so the row carries VLAN 101 only between that downlink and
the BlueField trunk. The untagged bootstrap path remains available for
recovery. This avoids carrying forward the stale Rock/`ether1` assumption from
the earlier USB-tether experiment.

The non-disruptive transition first added VLAN 100, VLAN 50, and `sfp56-8`'s
25G CR/RS-FEC settings while filtering remained off. The attended cutover then
made only two in-place changes: `vlan-filtering=no -> yes` and disabling the
old CRS fabric gateway. The live switch has remained in that state since
2026-08-28; rollback is still rendered separately and remains attended.

For review, `crs812-routeros-staged-show` renders the gated bridge-port, VLAN,
and physical-Ethernet target without enabling those gates in the normal
derivation. It is not an apply path. Its VLAN 100 row must continue to contain
only tagged `qsfp56-1-1` and untagged `sfp56-8`, and the bridge resource must
continue to say `vlan_filtering = false`.

## Pin and evaluation

The fork lives at `/mnt/Home/src/nix-routeros`, on branch
`crs812-adoption`, with current tip
`d549aa410d053a7bd7e5c1aa95fa3ad13b9e26eb` (based on upstream commit
`96c21ad3fce8925d77970bf702c545957bbdb3b9`). Add it to the fleet flake as a
local git input after committing the fork:

```nix
nix-routeros = {
  url = "git+file:///mnt/Home/src/nix-routeros?ref=crs812-adoption&rev=d549aa410d053a7bd7e5c1aa95fa3ad13b9e26eb&shallow=1";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

The input should be locked with `nix flake lock --update-input nix-routeros`.
The root flake can then expose a package with:

```nix
crs812-routeros = import ./machines/routeros/crs812/terranix.nix {
  inherit inputs pkgs;
  system = "x86_64-linux";
};
# The derivation itself is the show script; the other scripts are passthru
# attributes on it.
crs812-routeros-show = crs812-routeros;
crs812-routeros-plan = crs812-routeros.plan;
```

Do not expose the apply script during the import-only phase.

Do not put `TF_VAR_routeros_password` in Nix. The upstream helper expects
`FLAKE_DIR` and reads the password from the environment at plan/apply time;
use a protected shell secret manager for it.

## Existing-state bootstrap and attended cutover

The provider identifies existing RouterOS objects by IDs. First export a
backup and discover IDs over the existing SSH key path, then import only the
resources listed in the ownership boundary. The live CRS812 currently reports
bridge `*24`, bridge-port IDs `*0` through `*23` (hexadecimal), the staged VPP
VLAN row `*2`, management IP `*2`, and RouterOS 7.24rc4. The checked-in
`imports.nix` claims the existing bridge, management IP, supported system
singletons, and switch chip. Bridge ports, VLAN rows, physical Ethernet,
IP-service, and neighbor-discovery resources are explicitly disabled in phase
one; their desired values remain in `config.nix` for later ownership phases.
Confirm every ID immediately before importing, because IDs can change after an
object is removed/recreated.

```sh
export FLAKE_DIR=$PWD
nix run .#crs812-routeros-show | jq .
nix run .#crs812-routeros-staged-show | jq .
nix run .#crs812-routeros-plan
```

For an existing state directory, use the generated Terraform address names
and import IDs, for example:

```sh
tofu -chdir=machines/routeros/crs812/.state import \
  routeros_interface_bridge.bridge '*24'
tofu -chdir=machines/routeros/crs812/.state import \
  routeros_ip_address.bridge '*2'
```

Bridge-port and VLAN IDs must be discovered from the live device; the
provider's bridge VLAN resource accepts RouterOS IDs such as `*0`. The final
ownership import on 2026-08-28 was guarded by a saved plan whose machine-read
summary was `37 imports, 0 mutations, 0 destroys`; the post-import plan was
empty. Provider readback warnings for unsupported counters and RouterOS 7.24
fields are noisy but do not represent desired changes.

The flake exposes show/plan commands for `transition`, `cutover`, and
`rollback`, but no apply package. Applying remains an attended raw OpenTofu
operation after inspecting a saved plan. Before the cable move, the cutover
plan must remain exactly two in-place changes and zero destroys. The rollback
renderer restores adoption state and deletes only the two VLAN rows that this
migration created.
