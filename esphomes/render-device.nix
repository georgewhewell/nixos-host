{
  device ? let
    v = builtins.getEnv "ESPHOME_NIX_DEVICE";
  in
    if v != "" then v else throw "Set ESPHOME_NIX_DEVICE or pass { device = ...; }",
  system ? let
    v = builtins.getEnv "NIX_SYSTEM";
  in
    if v != "" then v else builtins.currentSystem,
  pkgs ? let
    ref = let
      v = builtins.getEnv "ESPHOME_NIX_NIXPKGS";
    in
      if v != "" then v else "nixpkgs";
  in
    (builtins.getFlake ref).legacyPackages.${system},
}: let
  lib = import ./lib.nix {inherit pkgs;};
  evaled = lib.evalNamedDevice {name = device;};
  failedAssertions = builtins.filter (a: !a.assertion) evaled.config.assertions;
  assertionMessage =
    "ESPHome module assertions failed for ${device}:\n"
    + builtins.concatStringsSep "\n" (builtins.map (a: "- ${a.message}") failedAssertions);
in
  if failedAssertions != []
  then throw assertionMessage
  else lib.yamlFormat.generate "${device}.yaml" evaled.config.esphome.settings
