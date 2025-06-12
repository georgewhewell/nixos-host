{
  inputs,
  lib,
  pkgs,
  ...
}: let
  bridgeName = "br0.lan";
in {
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

  hardware.cpu.amd.ryzen-smu.enable = true;

  # boot.kernelPackages = pkgs.linuxPackages_latest;
  # deployment.targetHost = "satanic.link";
  deployment.targetHost = "192.168.23.1";
  deployment.targetUser = "grw";

  system.stateVersion = "24.11";

  services.gcp-ddns = {
    enable = true;
    projectId = "domain-owner";
    zoneName = "satanic-link";
    records = [
      {
        name = "satanic.link.";
        type = "A";
        ttl = 300;
      }
      {
        name = "*.satanic.link.";
        type = "A";
        ttl = 300;
      }
      {
        name = "satanic.link.";
        type = "AAAA";
        ttl = 300;
      }
      {
        name = "router.satanic.link.";
        type = "AAAA";
        ttl = 300;
      }
    ];
    interval = "5m";
  };

  imports = with inputs.nixos-hardware.nixosModules; [
    common-cpu-amd
    common-cpu-amd-pstate
    common-cpu-amd-zenpower

    ../../../profiles/headless.nix
    ../../../profiles/uefi-boot.nix
    ../../../profiles/common.nix
    ../../../profiles/home.nix

    # common-cpu-amd-raphael-igpu
    # common-gpu-amd
    #  ../../../profiles/radeon.nix
    #
    ../../../profiles/router/linux.nix
    ../../../profiles/router/services.nix
    ../../../containers/unifi.nix
    ../../../services/buildfarm-slave.nix
  ];

  systemd.network.networks."20-nanokvm" = {
    matchConfig.Driver = "rndis_host";
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

  # add a bridge for thunderbolt
  #     netdevs = {
  systemd.network.netdevs."20-${bridgeName}" = {
    netdevConfig = {
      Kind = "bridge";
      Name = bridgeName;
    };
  };

  systemd.network.networks."20-thunderbolt" = {
    matchConfig.Driver = "thunderbolt-net";
    networkConfig.Bridge = bridgeName;
    linkConfig.RequiredForOnline = "enslaved";
  };

  services = {
    iperf3 = {
      enable = true;
      openFirewall = true;
    };
    hardware.bolt.enable = true;
  };

  networking.hosts = {
    "192.168.23.8" = ["trex.satanic.link"];
  };

  boot.kernelParams = [
    "pci=realloc=off"
  ];

  boot.initrd.kernelModules = [
    "nf_tables"
    "nft_compat"
    "igc"
    "ixgbe"
    "vfio"
    "mlx5_core"
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

  # Override kernel packages to use ZFS staging branch
  boot.kernelPackages = pkgs.linuxPackages_latest.extend (final: prev: {
    zfs_2_3 = prev.zfs_2_3.overrideAttrs (oldAttrs: {
      src = pkgs.fetchFromGitHub {
        owner = "openzfs";
        repo = "zfs";
        rev = "master";
        hash = "sha256-ZlrQC1NBZaxquCEu4IHn+5ZnmJi44gmdbCVzrAKabw4=";
      };
      version = "2.3.3-staging";
    });
  });
}
