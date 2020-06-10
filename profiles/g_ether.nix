{ config, lib, pkgs, ... }:
let
  bridgeName = "br0";
in
{

  fileSystems."/export/store" = {
    device = "/nix/store";
    options = [ "bind" "ro" ];
  };

  services.nfs.server = {
    enable = true;
    exports = ''
      /export                192.168.23.0/24(rw,fsid=0,no_subtree_check)
      /export/store          192.168.23.0/24(ro,no_root_squash,nohide,all_squash,anonuid=1000,anongid=1000,insecure,no_subtree_check)
    '';
  };

  networking.firewall.allowedTCPPorts = [
    111 # nfs?
    2049 # nfs
    4000
    4001
    4002
    4003
    138 # smb
    445 # smb
    548 # netatalk
    10809 # nbd

    # nfs
    20048
    40531
    46675
  ];

  networking.firewall.allowedUDPPorts = [
    111 # nfs?
    2049 # nfs
    138 # smb
    445 # smb

    # nfs
    20048
    37914
    42074
  ];
  /*# Create an empty bridge
networking.bridges.${bridgeName} = {
  interfaces = [];
};

networking.interfaces.${bridgeName} = {
  ipAddress = "10.0.10.1/24";
};*/

  # Auto-chmod pre-boot devices and trigger bridge job for new interfaces
  services.udev.extraRules = ''
    SUBSYSTEM=="usb", ATTRS{idVendor}=="13d3", ATTRS{idProduct}=="3404", ATTR{authorized}="0"

    # Rename and chown to users
    SUBSYSTEM=="usb", ATTRS{idVendor}=="04e8", ATTRS{idProduct}=="1234", GROUP="users", MODE="0660", SYMLINK+="usb-loader-m3"
    SUBSYSTEM=="usb", ATTRS{idVendor}=="1f3a", ATTRS{idProduct}=="efe8", GROUP="users", MODE="0660", SYMLINK+="sunxi-fel"
    SUBSYSTEM=="usb", ATTRS{idVendor}=="2207", ATTRS{idProduct}=="330c", GROUP="users", MODE="0660", SYMLINK+="rockchip-rk3399"

    SUBSYSTEM=="usb", ATTRS{idVendor}=="0e8d", ATTRS{idProduct}=="2000", ENV{ID_MM_DEVICE_IGNORE}="1", GROUP="users", MODE="0660", SYMLINK+="mtk-preloader"

    SUBSYSTEM=="usb", ATTRS{idVendor}=="0483", ATTRS{idProduct}=="0483", GROUP="users", MODE="0660", SYMLINK+="stm32"
    SUBSYSTEM=="usb", ATTRS{idVendor}=="0483", ATTRS{idProduct}=="df11", GROUP="users", MODE="0660", SYMLINK+="stm32-dfu"

    # VIA Labs, Inc. USB3.0 Hub
    SUBSYSTEM=="usb", ATTRS{idVendor}=="2109", ATTRS{idProduct}=="2811", GROUP="users", MODE="0660", SYMLINK+="smart-hub"

    # platform usb
    SUBSYSTEM=="net" KERNEL=="enp*u[0-9]", DRIVERS=="rndis_host", RUN+="${pkgs.systemd}/bin/systemctl --no-block start bridge-rndis@%k.service"
    SUBSYSTEM=="net" KERNEL=="enp*u[0-9]", DRIVERS=="cdc_eem", RUN+="${pkgs.systemd}/bin/systemctl --no-block start bridge-rndis@%k.service"

  '';

  # Add new interface to bridge
  systemd.services."bridge-rndis@" = {
    bindsTo = [ "sys-subsystem-net-devices-%i.device" ];
    serviceConfig = {
      Type = "simple";
      ExecStartPre = "${pkgs.bridge-utils}/bin/brctl setfd ${bridgeName} 0";
      ExecStart = "${pkgs.stdenv.shell} -c '${pkgs.bridge-utils}/bin/brctl addif ${bridgeName} %I && ${pkgs.iproute}/bin/ip addr add 0.0.0.0 dev %I'";
      ExecStartPost = "${pkgs.stdenv.shell} -c '${pkgs.inetutils}/bin/ifconfig %I up'";
    };
  };

  networking.firewall.allowedTCPPortRanges = [{ from = 50000; to = 51000; }];

}
