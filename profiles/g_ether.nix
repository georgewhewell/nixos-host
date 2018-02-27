{ config, lib, pkgs, ... }:

let
  bridgeName = "br0";
in {

  /*# Create an empty bridge
  networking.bridges.${bridgeName} = {
    interfaces = [];
  };

  networking.interfaces.${bridgeName} = {
    ipAddress = "10.0.10.1/24";
  };*/

  # Auto-chmod pre-boot devices and trigger bridge job for new interfaces
  services.udev.extraRules = ''
    # Rename and chown to plugdev
    SUBSYSTEM=="usb", ATTRS{idVendor}=="04e8", ATTRS{idProduct}=="1234", GROUP="users", MODE="0660" SYMLINK+="usb-loader-m3"
    SUBSYSTEM=="usb", ATTRS{idVendor}=="1f3a", ATTRS{idProduct}=="efe8", GROUP="users", MODE="0660" SYMLINK+="sunxi-fel"
    SUBSYSTEM=="usb", ATTRS{idVendor}=="2207", ATTRS{idProduct}=="330c", GROUP="users", MODE="0660" SYMLINK+="rockchip-rk3399"

    SUBSYSTEM=="usb", ATTRS{idVendor}=="0483", ATTRS{idProduct}=="0483", GROUP="users", MODE="0660" SYMLINK+="stm32"
    SUBSYSTEM=="usb", ATTRS{idVendor}=="0483", ATTRS{idProduct}=="df11", GROUP="users", MODE="0660" SYMLINK+="stm32-dfu"

    # VIA Labs, Inc. USB3.0 Hub
    SUBSYSTEM=="usb", ATTRS{idVendor}=="2109", ATTRS{idProduct}=="2811", GROUP="users", MODE="0660" SYMLINK+="smart-hub"

    # platform usb
    SUBSYSTEM=="net" KERNEL=="enp0s2*u[0-9]", DRIVERS=="rndis_host", \
      RUN+="${pkgs.systemd}/bin/systemctl --no-block start bridge-rndis@%k.service"

    # 3p usb
    SUBSYSTEM=="net" KERNEL=="enp3s0*u[0-9]", DRIVERS=="rndis_host", \
      RUN+="${pkgs.systemd}/bin/systemctl --no-block start bridge-rndis@%k.service"

  '';

  # Add new interface to bridge
  systemd.services."bridge-rndis@" = {
    bindsTo = [ "sys-subsystem-net-devices-%i.device"];
    serviceConfig = {
      Type = "simple";
      ExecStartPre = "${pkgs.bridge-utils}/bin/brctl setfd ${bridgeName} 0";
      ExecStart = "${pkgs.stdenv.shell} -c '${pkgs.bridge-utils}/bin/brctl addif ${bridgeName} %I && ${pkgs.iproute}/bin/ip addr add 0.0.0.0 dev %I'";
    };
  };

  networking.firewall.allowedTCPPortRanges = [ {from = 50000; to = 51000; } ];

}
