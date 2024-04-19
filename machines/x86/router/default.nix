{ config, pkgs, lib, inputs, ... }:

{
  /*
    router: xeon-d embedded
  */
  sconfig = {
    profile = "server";
    home-manager = {
      enable = true;
      enableVscodeServer = true;
    };
    wireguard = {
      enable = true;
    };
    vpp-router = {
      enable = true;
      dpdks = [
        # 10G
        "0000:01:00.0"
        "0000:01:00.1"

        # # 1G
        # "0000:03:00.0"
        # "0000:03:00.1"
        # "0000:03:00.2"
        # "0000:03:00.3"

        # 25G
        "0000:85:01.0"
        "0000:85:11.0"
      ];
      trunk = "VirtualFunctionEthernet133/17/0";
      downstream = [
        "VirtualFunctionEthernet133/1/0"
        "TenGigabitEthernet1/0/0"
        "TenGigabitEthernet1/0/1"
        # "GigabitEthernet3/0/0"
        # "GigabitEthernet3/0/1"
        # "GigabitEthernet3/0/2"
        # "GigabitEthernet3/0/3"
      ];
      inside_subnet = 23;
      forwardedPorts = {
        "192.168.23.254" = [
          22 # ssh
        ];
        "192.168.23.5" = [
          443 # https
          8333 # bitcoind
          9000 # lighthouse
          9001 # tor
          18080 # monero
          17026 # qbittorrent
          30303 # geth
          51820 # wireguard
          51413 # transmission
        ];
      };
    };
  };

  environment.systemPackages = with pkgs; [
    btop
    wirelesstools
    bridge-utils
    ethtool
    tcpdump
    conntrack-tools
    pciutils
  ];

  deployment.targetHost = "192.168.23.254";

  imports =
    [
      ../../../profiles/common.nix
      ../../../profiles/home.nix
      ../../../profiles/headless.nix
      ../../../profiles/uefi-boot.nix
    ];

  services.iperf3 = {
    enable = true;
    openFirewall = true;
  };

  boot.kernelPackages = pkgs.linuxPackages_latest;
  # boot.kernelPackages = pkgs.linuxPackages_latest_lto_icelake;
  boot.kernelParams = [ "intel_pstate=active" "isolcpu=2,3" ];

  boot.initrd.kernelModules = [
    "nf_tables"
    "nft_compat"
    "ixgbe"
    "igb"
    "i40e"
    "ice"
  ];

  fileSystems."/" =
    {
      device = "/dev/disk/by-uuid/0896549a-c162-4458-a0bb-3f397f91f538";
      fsType = "ext4";
    };

  fileSystems."/boot" =
    {
      device = "/dev/disk/by-uuid/2A3E-BFEC";
      fsType = "vfat";
    };

  networking = {
    hostName = "router";
    hostId = lib.mkForce "deadbeef";
    firewall.enable = false;
  };

}
