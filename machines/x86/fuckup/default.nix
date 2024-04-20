{ config, pkgs, lib, ... }:

{
  /*
    fuckup: skylake desktop
  */
  sconfig = {
    profile = "desktop";
    home-manager = {
      enable = true;
      enableGraphical = true;
      enableVscodeServer = true;
    };
    vpp-router = {
      enable = false;
      dpdks = [
        # 1G
        "0000:00:1f.6"

        # 25G
        "0000:01:00.0"
        "0000:01:00.1"
      ];
      trunk = "TwentyFiveGigabitEthernet1/0/0";
      downstream = [
        "TwentyFiveGigabitEthernet1/0/1"
        # "GigabitEthernet0/31/6"
      ];
      inside_subnet = 23;
      forwardedPorts = {
        "192.168.23.252" = [
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
          51413 # transmission
        ];
      };
    };
  };

  imports =
    [
      ../../../profiles/common.nix
      ../../../profiles/development.nix
      # ../../../profiles/bridge-interfaces.nix
      ../../../profiles/home.nix
      ../../../profiles/nas-mounts.nix
      ../../../profiles/uefi-boot.nix
      ../../../profiles/graphical.nix
      ../../../profiles/radeon.nix
      ../../../profiles/intel-gfx.nix
      # ../../../profiles/fastlan.nix

      ../../../services/buildfarm-slave.nix
      ../../../services/buildfarm-executor.nix

    ];

  # boot.kernelPackages = pkgs.linuxPackages_latest_lto_skylake;
  boot.kernelParams = [ "pci=realloc" "intel_iommu=on" "iommu=pt" ];

  system.stateVersion = "22.11";
  services.iperf3 = {
    enable = true;
    openFirewall = true;
  };
  fileSystems."/" =
    {
      device = "/dev/mapper/vg1-nixos";
      fsType = "f2fs";
    };

  fileSystems."/home/grw" =
    {
      device = "/dev/mapper/vg1-home";
      fsType = "f2fs";
    };

  fileSystems."/boot" =
    {
      device = "/dev/nvme0n1p1";
      fsType = "vfat";
    };

  environment.etc."OpenCL/vendors" = {
    mode = "symlink";
    source = "/run/opengl-driver/etc/OpenCL/vendors";
  };

  nix.settings.max-jobs = lib.mkDefault 4;
  zramSwap.enable = true;

  systemd.network =
    let
      bridgeName = "br0";
    in
    {
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
        # "50-usbeth" = {
        #   matchConfig.Driver = "r8152";
        #   networkConfig = {
        #     Bridge = bridgeName;
        #     ConfigureWithoutCarrier = true;
        #   };
        #   linkConfig.RequiredForOnline = "enslaved";
        # };
        # "40-br0" = {
        #   matchConfig.Name = bridgeName;
        #   bridgeConfig = { };
        #   address = [
        #     "192.168.23.7/24"
        #   ];
        #   routes = [
        #     { routeConfig.Gateway = "192.168.23.1"; }
        #   ];
        #   networkConfig = {
        #     ConfigureWithoutCarrier = true;
        #     IPv6AcceptRA = true;
        #   };
        # };
        # "10-lan-10g" = {
        #   matchConfig.Driver = "ixgbe";
        #   networkConfig = {
        #     Bridge = bridgeName;
        #     ConfigureWithoutCarrier = true;
        #   };
        #   linkConfig.RequiredForOnline = "enslaved";
        # };
        "10-lan" = {
          matchConfig.Name = "enp0s31f6";
          networkConfig = {
            Bridge = bridgeName;
            ConfigureWithoutCarrier = true;
          };
          linkConfig.RequiredForOnline = "enslaved";
        };
      };
    };

  networking = {
    hostName = "fuckup";
    wireless.enable = false;
    useDHCP = false;
    # enableIPv6 = true;
    nameservers = [ "192.168.23.5" ];

    firewall = {
      enable = true;
      allowedTCPPortRanges = [{ from = 5000; to = 5005; } { from = 50000; to = 60000; }];
      allowedUDPPortRanges = [{ from = 6000; to = 6005; } { from = 35000; to = 65535; }];
      allowedUDPPorts = [ 111 5353 40601 ];
      allowedTCPPorts = [
        9100
        10809
        8880
        8080
        /* shairport */
        3689
        5353

        39375 # ?? lol
        36383
        41815 # nfs??
        45085
        57747 # rpcinfo -p
      ];
      checkReversePath = false;
    };
  };
}
