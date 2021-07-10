{ lib }:
let
  machines = [
    "fuckup"
    "yoga"
    "nixhost"
    "installer"
    "workvm"
    "router"
    "hetzner"
  ];
in
lib.genAttrs machines (name:
  import (./. + "/${name}/configuration.nix"))
