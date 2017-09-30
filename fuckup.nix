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

  systemd.services.prometheus-node-exporter = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      TimeoutStartSec = 0;
      Restart = "always";
      ExecStart = ''${pkgs.prometheus-node-exporter}/bin/node_exporter
      '';
    };
  };

  systemd.services."dbus-org.bluez".serviceConfig.ExecStart = "${pkgs.bluez}/sbin/bluetoothd -n -d --compat";

}
