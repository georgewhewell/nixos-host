{ config, lib, pkgs, ... }:

let
  bridgeName = "br0";
in {
  services.udev.extraRules = ''
    SUBSYSTEM=="usb", ACTION=="add", \
        ATTR{idVendor}=="1d6b", ATTR{idProduct}=="0104", \
        RUN+="${pkgs.stdenv.shell} -c '${pkgs.bridge-utils}/bin/brctl addif ${bridgeName} enp3s0u1u4u4'}
  '';

}
