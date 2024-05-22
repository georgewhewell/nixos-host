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
      ../../../services/buildfarm-executor.nix
      ../../../services/buildfarm-slave.nix
    ];

  deployment.targetHost = "trex.satanic.link";
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
      "pci=realloc=off" # fixes: only 7 of 8 downstream work
      "pcie=pcie_bus_perf"
    ];
    initrd.kernelModules = [ "mlx5_core" "lm92" ];
  };
  boot.binfmt.emulatedSystems = [
    "aarch64-linux"
  ];
  fileSystems."/" =
    {
      device = "pool3d/root/trex-root";
      fsType = "zfs";
      options = [ "noatime" ];
    };

  fileSystems."/boot" =
    {
      device = "/dev/disk/by-uuid/37D0-505A";
      fsType = "vfat";
      options = [ "iocharset=iso8859-1" "fmask=0022" "dmask=0022" ];
    };

  fileSystems."/home/grw" =
    {
      device = "pool3d/root/grw-home";
      fsType = "zfs";
      options = [ "noatime" "nofail" ];
    };

  services = {
    fstrim.enable = true;
    fwupd.enable = true;
    hardware = {
      bolt.enable = true;
      openrgb.enable = true;
    };
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

  systemd.network =
    let
      bridgeName = "br0";
      bondName = "bond0";
    in
    {
      enable = true;
      wait-online.anyInterface = true;
      netdevs = {
        "20-${bridgeName}" = {
          netdevConfig = {
            Kind = "bridge";
            Name = bridgeName;
          };
        };
        # "10-${bondName}" = {
        #   netdevConfig = {
        #     Kind = "bond";
        #     Name = "bond0";
        #   };
        #   bondConfig = {
        #     Mode = "balance-rr";
        #     TransmitHashPolicy = "layer3+4";
        #   };
        # };
      };
      networks = {
        "99-ipheth" = {
          matchConfig.Driver = "ipheth";
          networkConfig = {
            DHCP = "ipv4";
            IPv6AcceptRA = true;
            DNSOverTLS = true;
            DNSSEC = true;
            IPv6PrivacyExtensions = false;
            IPForward = true;
            IgnoreCarrierLoss = true;
          };
          dhcpV4Config = {
            RouteMetric = 99;
            UseDNS = true;
            UseDomains = false;
            SendRelease = true;
          };
          linkConfig.RequiredForOnline = "no";
        };
        "50-usbeth" = {
          matchConfig.Driver = "r8152";
          networkConfig = {
            Bridge = bridgeName;
            ConfigureWithoutCarrier = true;
          };
          linkConfig.RequiredForOnline = "enslaved";
        };
        "20-thunderbolt" = {
          matchConfig.Driver = "thunderbolt-net";
          linkConfig = {
            RequiredForOnline = "carrier";
          };
          networkConfig = {
            Bridge = bridgeName;
            LinkLocalAddressing = "no";
          };
          # networkConfig.RequiredForOnline = "routeable";
        };
        "10-lan-10g" = {
          matchConfig.Driver = "i40e";
          linkConfig = {
            RequiredForOnline = "carrier";
          };
          networkConfig = {
            Bridge = bridgeName;
            LinkLocalAddressing = "no";
          };
          # networkConfig.RequiredForOnline = "routeable";
        };
        "10-lan-25g" = {
          matchConfig.Driver = "mlx5_core";
          networkConfig.Bridge = bridgeName;
        };

        # "10-${bondName}" = {
        #   matchConfig.Name = bondName;
        #   linkConfig = {
        #     RequiredForOnline = "carrier";
        #   };
        #   networkConfig = {
        #     Bridge = bridgeName;
        #     LinkLocalAddressing = "no";
        #   };
        # };
        "05-${bridgeName}" = {
          matchConfig.Name = bridgeName;
          bridgeConfig = { };
          address = [
            "192.168.23.8/24"
          ];
          routes = [
            { routeConfig.Gateway = "192.168.23.1"; }
          ];
          networkConfig = {
            DNSOverTLS = true;
            DNSSEC = true;
            IPv6PrivacyExtensions = false;
            IPForward = true;
            IgnoreCarrierLoss = true;
            ConfigureWithoutCarrier = true;
            IPv6AcceptRA = true;
          };
        };
      };
    };
}
