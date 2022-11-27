{ lib }:
let
  machines = [
    "fuckup"
    "yoga"
    "nixhost"
    "installer"
    "workvm"
    "hetzner"
  ];
in
lib.genAttrs machines (name: import (./. + "/${name}/configuration.nix"))
