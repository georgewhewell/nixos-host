{ lib }:

let
  machines = [
    "odroid-c2"
    "nanopi-neo2"
    "orangepi-prime"
    "rock64"
    "tvheadend"
    "nanopi-m3"
    "amlogic-s912"
  ];
in
  lib.genAttrs machines (name:
      import (./. + "/${name}/configuration.nix"))
