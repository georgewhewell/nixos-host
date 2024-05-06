{ config, pkgs, lib, ... }:

{
  /*
    trex: trx90 system
  */
  sconfig = {
    profile = "desktop";
    home-manager = {
      enable = true;
      enableGraphical = true;
      enableVscodeServer = true;
    };
  };

  imports =
    [
      ../../../profiles/common.nix
      ../../../profiles/home.nix
      ../../../profiles/development.nix
      ../../../profiles/headless.nix
      ../../../profiles/uefi-boot.nix
      ../../../profiles/graphical.nix
      ../../../profiles/radeon.nix
      ../../../profiles/nas-mounts.nix
      ../../../services/buildfarm-slave.nix
    ];

  deployment.targetHost = "192.168.23.8";
  deployment.targetUser = "grw";

  boot.supportedFilesystems = [ "ext4" "vfat" "xfs" "zfs" "bcachefs" ];
  boot = {
    kernelModules = [
      "ipmi_devintf"
      "ipmi_si"
    ];
    kernelPackages = pkgs.linuxPackages_latest;
    kernelParams = [
      "amd_iommu=on"
      "pci=realloc=off"
      "pcie=pcie_bus_perf"
    ];
    initrd.kernelModules = [ "mlx5_core" "lm92" ];
  };

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

  # fileSystems."/3draid" =
  #   {
  #     device = "/dev/md127";
  #     fsType = "xfs";
  #     neededForBoot = false;
  #     options = [ "noatime" "discard" "nofail" ];
  #   };

  # boot.swraid = {
  #   enable = true;
  # };

  services = {
    fstrim.enable = true;
    fwupd.enable = true;
    hardware.bolt.enable = true;
    thermald.enable = true;
    iperf3.enable = true;
    irqbalance.enable = true;
  };

  environment.systemPackages = with pkgs; [ pciutils fio lm_sensors ];

  networking = {
    hostName = "trex";
    hostId = lib.mkForce "deadbeef";
    enableIPv6 = true;
    useNetworkd = true;
    nameservers = [ "192.168.23.5" ];
    firewall.enable = false;
  };

  systemd.network = {
    enable = true;
    wait-online.anyInterface = true;

    # netdevs = {
    #   "20-${bridgeName}" = {
    #     netdevConfig = {
    #       Kind = "bridge";
    #       Name = bridgeName;
    #     };
    #   };
    # };

    networks = {
      # "99-ipheth" = {
      #   matchConfig.Driver = "ipheth";
      #   networkConfig = {
      #     DHCP = "ipv4";
      #     IPv6AcceptRA = true;
      #     DNSOverTLS = true;
      #     DNSSEC = true;
      #     IPv6PrivacyExtensions = false;
      #     IPForward = true;
      #     IgnoreCarrierLoss = true;
      #   };
      #   dhcpV4Config = {
      #     RouteMetric = 99;
      #     UseDNS = true;
      #     UseDomains = false;
      #     SendRelease = true;
      #   };
      #   linkConfig.RequiredForOnline = "no";
      # };
      "10-lan-10g" = {
        matchConfig.Driver = "ixgbe";
        networkConfig.DHCP = "ipv4";
        # networkConfig.RequiredForOnline = "routeable";
      };
      "10-lan-25g" = {
        matchConfig.Driver = "mlx5_core";
        address = [
          "192.168.23.8/24"
        ];
        routes = [
          { routeConfig.Gateway = "192.168.23.1"; }
        ];
        networkConfig = {
          ConfigureWithoutCarrier = true;
          IPv6AcceptRA = true;
        };

        # networkConfig = {
        #   DHCP = "ipv4";
        #   IPv6AcceptRA = true;
        #   DNSOverTLS = true;
        #   DNSSEC = true;
        #   IPv6PrivacyExtensions = false;
        #   IPForward = true;
        #   IgnoreCarrierLoss = true;
        #   dhcpV4Config = {
        #     RouteMetric = 1;
        #     UseDNS = true;
        #     UseDomains = false;
        #     SendRelease = true;
        #   };
        #   # ConfigureWithoutCarrier = true;
        # };
        linkConfig.RequiredForOnline = "routable";
      };
    };
  };
}
