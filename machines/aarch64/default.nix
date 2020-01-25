{ lib }: 

let
  machines = [
    "odroid-c2"
    "orangepi-pc2"
    "rock64"
    "tvheadend"
    "router"
    "nanopi-m3"
#    "amlogic-s912"
  ];
in
  lib.genAttrs machines (name:
      import (./. + "/${name}/configuration.nix"))
