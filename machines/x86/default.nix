{ lib }: 

let
  machines = [
    "fuckup"
    "yoga"
    "nixhost"
    "installer"
    "workvm"
  ];
in
  lib.genAttrs machines (name:
      import (./. + "/${name}/configuration.nix"))
