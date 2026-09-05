# CRS812 nix-routeros adoption

This is a staged OpenTofu/Terranix control-plane adoption. The existing
[`machines/routeros/crs812/config.rsc`](machines/routeros/crs812/config.rsc)
remains authoritative for the switch-chip and platform-specific parts of the
CRS812 migration.

## Ownership boundary

The local `nix-routeros` fork models the stable RouterOS API resources that are
safe to import: the identity and management IP/service settings, the single
hardware bridge, bridge ports, the staged VPP lab VLAN row, physical Ethernet
MTU/speed/FEC settings, and the switch-wide L3HW/QoS-offload booleans. The fork
deliberately does not claim QoS profiles, tx-manager queues, PFC, or other
CRS812 switch-chip state. Those remain in `config.rsc` until the provider has
explicit schemas and a production import has been reviewed.

The generated config keeps `vlanFiltering = false`; enabling it is a cut-over
operation and must happen only after the full production VLAN table and WAN
cabling map are known.

The planned backup transit is VLAN 101, tagged on exactly two hybrid ports:
Rock's `ether1` and BlueField's `qsfp56-1-1`. The live read-only inventory
confirms those physical mappings; the VLAN-101 entry is present as desired
data but is not emitted during the import-only phase.

With the phase-one gates enabled, the generated plan has no bridge-port, VLAN,
or physical-Ethernet creates. It emits only the imported bridge, management IP,
system singleton/service resources, and switch-chip offload flags. A real
`tofu plan` can still show attribute drift if the device changes after the
read-only inventory; review that diff before any apply.

## Pin and evaluation

The fork lives at `/mnt/Home/src/nix-routeros`, on branch
`crs812-adoption`, with current tip
`2957cafbce71e40d27a57cc638aed243f3e27ff0` (based on upstream commit
`96c21ad3fce8925d77970bf702c545957bbdb3b9`). Add it to the fleet flake as a
local git input after committing the fork:

```nix
nix-routeros = {
  url = "git+file:///mnt/Home/src/nix-routeros?ref=crs812-adoption&rev=2957cafbce71e40d27a57cc638aed243f3e27ff0&shallow=1";
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
# Expose the derivation's scripts as individual package outputs:
crs812-routeros-show = crs812-routeros.show;
crs812-routeros-plan = crs812-routeros.plan;
crs812-routeros-apply = crs812-routeros.apply;
```

Do not put `TF_VAR_routeros_password` in Nix. The upstream helper expects
`FLAKE_DIR` and reads the password from the environment at plan/apply time;
use a protected shell secret manager for it.

## Existing-state bootstrap (read-only until reviewed)

The provider identifies existing RouterOS objects by IDs. First export a
backup and discover IDs over the existing SSH key path, then import only the
resources listed in the ownership boundary. The live CRS812 currently reports
bridge `*24`, bridge-port IDs `*0` through `*23` (hexadecimal), the staged VPP
VLAN row `*2`, management IP `*2`, and RouterOS 7.24rc4. The checked-in
`imports.nix` claims the existing bridge, management IP, system singleton
resources, service names, and switch chip. Bridge ports, VLAN rows, and
physical Ethernet resources are explicitly disabled in phase one; their
desired values remain in `config.nix` for the later import phase. Confirm
every ID immediately before importing, because IDs can change after an object
is removed/recreated.

```sh
export FLAKE_DIR=$PWD
nix run .#crs812-routeros-show | jq .
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
provider's bridge VLAN resource accepts RouterOS IDs such as `*0`. Run
`tofu plan` after every import and review that no delete/recreate is proposed.
There is intentionally no `apply` command in the migration procedure yet.
