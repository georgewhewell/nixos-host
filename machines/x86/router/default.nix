{ config, pkgs, lib, ... }:

{
  /*
    router: xeon-d embedded
  */
  sconfig = {
    profile = "server";
    home-manager = {
      enable = true;
    };
    # vpp-router = {
    #   enable = false;
    #   dpdks = [
    #     # 10G
    #     "0000:01:00.0"
    #     "0000:01:00.1"

    #     # 1G
    #     "0000:03:00.0"
    #     "0000:03:00.1"
    #     "0000:03:00.2"
    #     "0000:03:00.3"

    #     # 25G
    #     "0000:85:00.0"
    #     "0000:85:00.2"
    #   ];
    #   trunk = "TwentyFiveGigabitEthernet85/0/2";
    #   downstream = [
    #     "TwentyFiveGigabitEthernet85/0/0"
    #     "TenGigabitEthernet1/0/0"
    #     "TenGigabitEthernet1/0/1"
    #     "GigabitEthernet3/0/0"
    #     "GigabitEthernet3/0/1"
    #     "GigabitEthernet3/0/2"
    #     "GigabitEthernet3/0/3"
    #   ];
    #   inside_subnet = 25;
    # };
  };

  imports =
    [
      # ../../../services/virt/host.nix
      ../../../profiles/common.nix
      ../../../profiles/home.nix
      ../../../profiles/headless.nix
      ../../../profiles/uefi-boot.nix

      # ../../../profiles/bridge-interfaces.nix
      ../../../profiles/router.nix
      ../../../profiles/fastlan.nix
    ];

  services.iperf3 = {
    enable = true;
    openFirewall = true;
  };

  services.udpxy = {
    enable = true;
  };

  boot.kernelPackages = pkgs.linuxPackages_latest_lto_icelake;
  nixpkgs.config.permittedInsecurePackages = [
    "nodejs-16.20.2"
  ];

  # boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.kernelParams = [ "intel_pstate=active" ];

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

  boot.kernelModules = [
    "ipmi_devintf"
    "ipmi_si"
    "vfio_pci"
    "ixgbe"
    "i40e"
    "igb"
    "ice"
  ];

  services.thermald.enable = true;

  networking = {
    hostName = "router";
    hostId = lib.mkForce "deadbeef";
    enableIPv6 = true;
  };
}
