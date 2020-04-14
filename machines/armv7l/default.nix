{ lib }:

let
  machines = [
    "bananapi-m3"
    "nanopi-air"
    "odroid-hc1"
    "orangepi-zero"
  ];
in
  lib.genAttrs machines
    (name: import (./. + "/${name}/configuration.nix"))
