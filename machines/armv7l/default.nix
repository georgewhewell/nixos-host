{ lib }: 

let
  machines = [
    "odroid-hc1"
    "bananapi-m3"
  ];
in
  lib.genAttrs machines 
    (name: import (./. + "/${name}/configuration.nix"))
