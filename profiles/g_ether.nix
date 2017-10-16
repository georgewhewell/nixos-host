{ config, lib, pkgs, ... }:

let
  bridgeName = "br0";
in {
  services.udev.extraRules = ''
    # Rename and chown to plugdev
    SUBSYSTEM=="usb", ATTRS{idVendor}=="1f3a", ATTRS{idProduct}=="efe8", GROUP="users", MODE="0660" SYMLINK+="sunxi-fel"
    SUBSYSTEM=="net" KERNEL=="enp0s20f0u*[0-9]", DRIVERS=="rndis_host", OPTIONS="last_rule", RUN+="${pkgs.systemd}/bin/systemctl --no-block start bridge-rndis@%k.service"
  '';

  systemd.services."bridge-rndis@" = {
    bindsTo = [ "sys-subsystem-net-devices-%i.device"];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.stdenv.shell} -c '${pkgs.bridge-utils}/bin/brctl addif br0 %I && ${pkgs.iproute}/bin/ip addr add 0.0.0.0 dev %I'";
    };
  };
}
