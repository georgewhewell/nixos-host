{ lib }:
let
  machines = [
    "bananapi-m3"
    "licheepi-zero"
    "nanopi-air"
    "nanopi-duo"
    "odroid-c1"
    "odroid-hc1"
    "orangepi-zero"
  ];
in
lib.genAttrs
  machines
  (name: import (./. + "/${name}/configuration.nix"))
