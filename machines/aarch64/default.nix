{ lib }:
let
  machines = [
    "odroid-c2"
    "nanopi-neo2"
    "rock64"
    "tvheadend"
    "orangepi-pc2"
    "nanopi-m3"
    "amlogic-s912"
  ];
in
lib.genAttrs machines (name:
  import (./. + "/${name}/configuration.nix"))
