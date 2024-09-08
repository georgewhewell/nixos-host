{ config, pkgs, lib, inputs, ... }:

{
  /*
    router: cwwk 8845hs board
  */
  sconfig = {
    profile = "server";
    home-manager = {
      enable = true;
      enableVscodeServer = false;
    };
    wireguard = {
      enable = false;
    };
  };

  # systemd.services.create-vfs = {
  #   description = "Create VFs on Mellanox NIC";
  #   after = [ "network.target" ];
  #   wantedBy = [ "multi-user.target" ];

  #   serviceConfig = {
  #     Type = "oneshot";
  #     ExecStart = "${pkgs.bash}/bin/bash -c 'echo 2 > /sys/class/net/enp1s0f1np1/device/sriov_numvfs'";
  #     RemainAfterExit = true;
  #   };
  # };

  # systemd.services.set-multicast = {
  #   description = "Set multicast";
  #   after = [ "network.target" ];
  #   wantedBy = [ "multi-user.target" ];

  #   serviceConfig = {
  #     Type = "oneshot";
  #     ExecStart = "${pkgs.iproute}/bin/ip link set enp1s0f1np1 allmulticast on";
  #     RemainAfterExit = true;
  #   };
  # };

  environment.systemPackages = with pkgs; [
    btop
    wirelesstools
    bridge-utils
    ethtool
    tcpdump
    conntrack-tools
    pciutils
    iperf
  ];

  deployment.targetHost = "192.168.23.1";
  deployment.targetUser = "grw";

  imports =
    [
      ../../../profiles/common.nix
      ../../../profiles/home.nix
      ../../../profiles/headless.nix
      ../../../profiles/uefi-boot.nix
      ../../../profiles/nas-mounts.nix
      ../../../profiles/router.nix
      ../../../profiles/radeon.nix
      ../../../services/nginx.nix
    ];

  services = {
    iperf3 = {
      enable = true;
      openFirewall = true;
    };
    hardware.bolt.enable = true;
  };

  boot.kernelPackages = pkgs.linuxPackages_latest;

  boot.kernelParams = [
    "amd_pstate=active"
    "pci=realloc=off"
  ];

  boot.initrd.kernelModules = [
    "nf_tables"
    "nft_compat"
    "igc"
    "mlx5_core"
  ];

  fileSystems."/" =
    {
      device = "zpool/root/nixos-router";
      fsType = "zfs";
    };

  fileSystems."/boot" =
    {
      device = "/dev/disk/by-uuid/5826-D605";
      fsType = "vfat";
      options = [ "fmask=0022" "dmask=0022" ];
    };

  networking = {
    hostName = "router";
    hostId = lib.mkForce "deadbeef";
    enableIPv6 = true;
  };
}
