{ config, pkgs, lib, ... }:

{
  /*
    trex: trx90 system
  */
  sconfig = {
    profile = "server";
    home-manager = {
      enable = true;
    };
  };

  imports =
    [
      ../../../profiles/common.nix
      ../../../profiles/home.nix
      ../../../profiles/headless.nix
      ../../../profiles/uefi-boot.nix

      # ../../../profiles/bridge-interfaces.nix
      ../../../profiles/fastlan.nix
    ];

  services.iperf3 = {
    enable = true;
    openFirewall = true;
  };

  services.irqbalance.enable = true;

  boot.kernelPackages = pkgs.linuxPackages_latest_lto_zen4;

  fileSystems."/" =
    {
      device = "/dev/disk/by-uuid/93f5fe29-1e12-4b84-95da-6b0e5888a53a";
      fsType = "ext4";
    };

  fileSystems."/boot" =
    {
      device = "/dev/disk/by-uuid/4A41-E197";
      fsType = "vfat";
    };


  boot.swraid.enable = true;

  /*
    fileSystems."/3draid" =
    {
      device = "/dev/md0";
      fsType = "xfs";
      neededForBoot = false;
    };
  */
  environment.systemPackages = with pkgs; [ pciutils fio ];

  boot.kernelModules = [
    "ipmi_devintf"
    "ipmi_si"
  ];

  services.thermald.enable = true;

  networking = {
    hostName = "trex";
    hostId = lib.mkForce "deadbeef";
    enableIPv6 = true;
  };
}
