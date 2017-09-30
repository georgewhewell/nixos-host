{ config, lib, pkgs, ... }:

let
  bridgeName = "br0";
in {
  services.udev.extraRules = ''

    KERNEL=="rndis_host", ACTION=="add", \
        RUN+="${pkgs.stdenv.shell} -c '${pkgs.bridge-utils}/bin/brctl addif ${bridgeName} $DEVNAME && ${pkgs.nettools}/bin/ifconfig $DEVNAME promisc'}
  '';

}
