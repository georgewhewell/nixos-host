{ config, pkgs, lib, ... }:

{
  /*
    nixhost: xeon-d microserver
  */
  sconfig = {
    profile = "server";
    home-manager = {
      enable = true;
      enableVscodeServer = true;
    };
  };

  deployment.targetHost = "nixos";
  deployment.targetUser = "nixos";

  environment.systemPackages = [ pkgs.vpp ];
  imports =
    [
      ../../../containers/unifi.nix

      ../../../profiles/bridge-interfaces.nix
      ../../../profiles/common.nix
      ../../../profiles/headless.nix
      ../../../profiles/uefi-boot.nix
      # ../../../profiles/router.nix
      ../../../profiles/router-vpp.nix
    ];

  boot.kernelPackages = pkgs.linuxPackages_latest_lto_icelake;
  boot.kernelParams = [ "intel_pstate=active" ];
  services.undervolt = {
    enable = true;
    p1 = {
      limit = 10;
      window = 10;
    };
  };

  powerManagement = {
    enable = true;
    cpuFreqGovernor = "powersave";
  };

  fileSystems."/" =
    {
      device = "/dev/mapper/vg1-nixos";
      fsType = "ext4";
    };

  fileSystems."/boot" =
    {
      device = "/dev/disk/by-label/EFI";
      fsType = "vfat";
    };

  services.iperf3 = {
    enable = true;
    openFirewall = true;
  };

  boot.kernelModules = [
    "ipmi_devintf"
    "ipmi_si"
  ];

  networking = {
    hostName = "gateway";
    hostId = lib.mkForce "deadbeef";
    firewall.checkReversePath = false;
  };
}
