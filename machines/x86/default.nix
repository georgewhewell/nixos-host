{ lib }:

let
  machines = [
    "fuckup"
    "yoga"
    "nixhost"
    "installer"
    "workvm"
    "router"
  ];
in
  lib.genAttrs machines (name:
      import (./. + "/${name}/configuration.nix"))
