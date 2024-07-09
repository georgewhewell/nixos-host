{ config, pkgs, lib, inputs, ... }:

{
  /*
    router: cwwk 8845hs board 
  */
  sconfig = {
    profile = "server";
    home-manager = {
      enable = false;
      enableVscodeServer = false;
    };
    wireguard = {
      enable = false;
    };
  };

  deployment.targetHost = "192.168.23.254";
  deployment.targetUser = "grw";

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

  fileSystems."/" =
    {
      device = "UUID=8b8990d8-15a7-4308-a51c-4e5b7a6898e1";
      fsType = "bcachefs";
    };

  fileSystems."/boot" =
    {
      device = "/dev/disk/by-uuid/2A3E-BFEC";
      fsType = "vfat";
      options = [ "fmask=0022" "dmask=0022" ];
    };

  networking = {
    hostName = "jellyfin";
    hostId = lib.mkForce "deadbeef";
    enableIPv6 = true;
  };
}
