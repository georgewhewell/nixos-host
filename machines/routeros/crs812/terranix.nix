# Staged OpenTofu/Terranix entry point for the CRS812.
#
# The fleet flake owns the nix-routeros input. Keeping this as a function makes
# the derivation easy to evaluate on the build host without putting RouterOS
# credentials in the Nix store or in the NixOS host closure.
{
  inputs,
  pkgs,
  system,
  network,
}: let
  configModule = import ./config.nix {inherit network;};
  adoptionConfigModule = import ./config.nix {
    inherit network;
    phase = "adoption";
  };
  transitionConfigModule = import ./config.nix {
    inherit network;
    phase = "transition";
  };
  cutoverConfigModule = import ./config.nix {
    inherit network;
    phase = "cutover";
  };
  baseModules = [
    configModule
    ./imports.nix
  ];
  staged = inputs.nix-routeros.lib.mkRouterDerivation {
    inherit pkgs system;
    name = "crs812-staged";
    stateDir = "machines/routeros/crs812/.state";
    modules =
      baseModules
      ++ [
        ({lib, ...}: {
          # Render the complete desired physical/VLAN resources for review, but
          # do not change the production module's import-only safety gates.
          routeros.bridge.managePorts = lib.mkForce true;
          routeros.bridge.manageVlanEntries = lib.mkForce true;
          routeros.interfaces.manageEthernetSettings = lib.mkForce true;
        })
      ];
  };
  ownership = inputs.nix-routeros.lib.mkRouterDerivation {
    inherit pkgs system;
    name = "crs812-ownership";
    stateDir = "machines/routeros/crs812/.state";
    modules = [
      adoptionConfigModule
      ./imports.nix
      ({lib, ...}: {
        # Exact live bridge/VLAN/Ethernet shape used only to import remaining
        # objects without changing the switch.
        routeros.bridge.managePorts = lib.mkForce true;
        routeros.bridge.manageVlanEntries = lib.mkForce true;
        routeros.interfaces.manageEthernetSettings = lib.mkForce true;
      })
    ];
  };
  transition = inputs.nix-routeros.lib.mkRouterDerivation {
    inherit pkgs system;
    name = "crs812-transition";
    stateDir = "machines/routeros/crs812/.state";
    modules = [
      transitionConfigModule
      ./imports.nix
      ({lib, ...}: {
        # Full transition JSON for review only. Filtering stays false and no
        # apply derivation is exposed by the fleet flake.
        routeros.bridge.managePorts = lib.mkForce true;
        routeros.bridge.manageVlanEntries = lib.mkForce true;
        routeros.interfaces.manageEthernetSettings = lib.mkForce true;
      })
    ];
  };
  cutover = inputs.nix-routeros.lib.mkRouterDerivation {
    inherit pkgs system;
    name = "crs812-cutover";
    stateDir = "machines/routeros/crs812/.state";
    modules = [
      cutoverConfigModule
      ./imports.nix
      ({lib, ...}: {
        # Render the exact handoff state, including vlan-filtering=yes and the
        # disabled legacy fabric gateway.  It remains show-only in flake.nix.
        routeros.bridge.managePorts = lib.mkForce true;
        routeros.bridge.manageVlanEntries = lib.mkForce true;
        routeros.interfaces.manageEthernetSettings = lib.mkForce true;
      })
    ];
  };
  safe = inputs.nix-routeros.lib.mkRouterDerivation {
    inherit pkgs system;
    name = "crs812";
    stateDir = "machines/routeros/crs812/.state";
    modules = baseModules;
  };
in
  safe
  // {
    inherit (safe) plan apply destroy;
    rollback = ownership;
    inherit staged ownership transition cutover;
  }
