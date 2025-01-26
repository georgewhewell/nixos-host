{
  pkgs,
  lib,
  inputs,
  ...
}: {
  /*
  router: cwwk 8845hs board
  */
  sconfig = {
    profile = "server";
    home-manager = {
      enable = true;
      enableVscodeServer = false;
    };
  };

  deployment.targetHost = "10.86.167.2";
  # deployment.targetHost = "192.168.23.254";
  deployment.targetUser = "grw";
  system.stateVersion = "24.11";

  imports = with inputs.nixos-hardware.nixosModules; [
    common-cpu-amd
    common-cpu-amd-pstate
    common-cpu-amd-raphael-igpu
    common-cpu-amd-zenpower
    common-gpu-amd
    ../../../containers/unifi.nix
    ../../../profiles/common.nix
    ../../../profiles/home.nix
    ../../../profiles/headless.nix
    ../../../profiles/uefi-boot.nix
    # ../../../profiles/nas-mounts.nix
    ../../../profiles/vpp-router.nix
    ../../../profiles/radeon.nix
    ../../../services/nginx.nix
    # ../../../services/jellyfin.nix
  ];

  systemd.network.networks."20-rndis" = {
    # nanokvm
    matchConfig.Driver = "rndis_host";
    # separate 10.86.167.1/24 network
    address = [
      "10.86.167.2/24"
    ];
    networkConfig = {
      DHCP = "no";
      IPv6AcceptRA = false;
      IPv6PrivacyExtensions = false;
      IPv6Forwarding = false;
      IgnoreCarrierLoss = true;
    };
  };

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
    "vfio"
  ];

  fileSystems."/" = {
    device = "zpool/root/nixos-router";
    fsType = "zfs";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/5826-D605";
    fsType = "vfat";
    options = ["fmask=0022" "dmask=0022"];
  };

  networking = {
    hostName = "router";
    hostId = lib.mkForce "deadbeef";
    enableIPv6 = true;
  };
}
