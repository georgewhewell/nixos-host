{ config, pkgs, lib, ... }:

{
  /*
    fuckup: skylake desktop
  */

  imports =
    [
      ./profiles/common.nix
      ./profiles/home.nix
      ./profiles/nas-mounts.nix
      ./profiles/uefi-boot.nix
      ./profiles/xserver.nix
      ./services/docker.nix
      ./services/virt/host.nix
      ./services/virt/vfio.nix
    ];

  fileSystems."/" =
    { device = "zpool/root/nixos";
      fsType = "zfs";
    };

  fileSystems."/boot" =
    { device = "/dev/disk/by-uuid/CD68-6C43";
      fsType = "vfat";
    };

  boot.extraModulePackages = [
    config.boot.kernelPackages.broadcom_sta ];

  nix.maxJobs = lib.mkDefault 8;
  powerManagement.cpuFreqGovernor = "performance";

  networking = {
    hostName = "fuckup";
    hostId = "deadbeef";
    useDHCP = true;
    useNetworkd = true;

    firewall = {
      enable = true;
      allowedTCPPorts = [ 9100 ];
      checkReversePath = false;
    };

    wireless = {
      enable = true;
      userControlled = true;
    };

    bridges.br0 = {
      interfaces = [ "enp0s31f6" "enp1s0f0" "enp1s0f1" ];
    };
  };

  services.xserver = {
    useGlamor = true;
    videoDrivers = [ "modesetting" ];
    xrandrHeads = [
      { output = "HDMI-2"; monitorConfig = ''
        Option "Rotate" "right"
        Option "Broadcast RGB" "Full"
        ''; }
      { output = "DP-1"; primary = true; monitorConfig = ''
        Option "Broadcast RGB" "Full"
    '';}
    ];
  };

  systemd.services."dbus-org.bluez".serviceConfig.ExecStart = "${pkgs.bluez}/sbin/bluetoothd -n -d --compat";


  services.udev.extraRules = ''
    # Rename and chown to plugdev
    SUBSYSTEM=="usb", ATTRS{idVendor}=="04e8", ATTRS{idProduct}=="1234", GROUP="users", MODE="0660" SYMLINK+="usb-loader-m3"
    SUBSYSTEM=="usb", ATTRS{idVendor}=="1f3a", ATTRS{idProduct}=="efe8", GROUP="users", MODE="0660" SYMLINK+="sunxi-fel"

    #  ACTION=="add", KERNEL=="usb*[0-9]", RUN+="${pkgs.systemd}/bin/systemctl --no-block start nanopi-m3-boot@%k.service"
    ACTION=="add", KERNEL=="enp0s20*", DRIVERS=="rndis_host", RUN+="${pkgs.systemd}/bin/systemctl --no-block start bridge-rndis@%k.service"
  '';

  systemd.services."bridge-rndis@" = {
    /*bindsTo = [ "dev-%i.device"] ;*/
    serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.stdenv.shell} -c '${pkgs.bridge-utils}/bin/brctl addif br0 %I && ${pkgs.nettools}/bin/ifconfig %I promisc on inet 0.0.0.0}'";
    };
  };

}
