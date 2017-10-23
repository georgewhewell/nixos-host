{ config, lib, pkgs, ... }:

let
  bridgeName = "br0";
in {
  services.udev.extraRules = ''
    # Rename and chown to plugdev
    SUBSYSTEM=="usb", ATTRS{idVendor}=="04e8", ATTRS{idProduct}=="1234", GROUP="users", MODE="0660" SYMLINK+="usb-loader-m3"
    SUBSYSTEM=="usb", ATTRS{idVendor}=="1f3a", ATTRS{idProduct}=="efe8", GROUP="users", MODE="0660" SYMLINK+="sunxi-fel"

    # VIA Labs, Inc. USB3.0 Hub
    SUBSYSTEM=="usb", ATTRS{idVendor}=="2109", ATTRS{idProduct}=="2811", GROUP="users", MODE="0660" SYMLINK+="smart-hub"

    # platform usb
    SUBSYSTEM=="net" KERNEL=="enp0s2*u[0-9]", DRIVERS=="rndis_host", \
      RUN+="${pkgs.systemd}/bin/systemctl --no-block start bridge-rndis@%k.service"

    # 3p usb
    SUBSYSTEM=="net" KERNEL=="enp3s0*u[0-9]", DRIVERS=="rndis_host", \
      RUN+="${pkgs.systemd}/bin/systemctl --no-block start bridge-rndis@%k.service"

  '';

  systemd.services."bridge-rndis@" = {
    bindsTo = [ "sys-subsystem-net-devices-%i.device"];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.stdenv.shell} -c '${pkgs.bridge-utils}/bin/brctl addif ${bridgeName} %I && ${pkgs.iproute}/bin/ip addr add 0.0.0.0 dev %I'";
    };
  };

  fileSystems."/export/store" = {
    device = "/nix/store";
    options = [ "bind" ];
  };

  services.nfs.server = {
    enable = true;
    statdPort = 4000;
    lockdPort = 4001;
    mountdPort = 4002;
    exports = ''
      /export                192.168.23.0/24(rw,fsid=0,no_subtree_check)
      /export/store          192.168.23.0/24(ro,async,nohide,all_squash,anonuid=1000,anongid=1000,insecure,no_subtree_check)
    '';
  };

  networking.firewall.allowPing = true;

  networking.firewall.allowedTCPPorts = [
    111  # nfs?
    2049 # nfs
    4000 # nfs/statd
    4001 # nfs/lockd
    4002 # nfs/mountd
  ];

  networking.firewall.allowedUDPPorts = [
    111  # nfs?
    2049 # nfs
    4000 # nfs/statd
    4001 # nfs/lockd
    4002 # nfs/mountd
  ];
}
