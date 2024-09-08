{ config, pkgs, lib, inputs, ... }:

{
  /*
    router: cwwk 8845hs board
  */
  sconfig = {
    profile = "server";
    home-manager = {
      enable = true;
      enableVscodeServer = false;
    };
    wireguard = {
      enable = false;
    };
  };

  deployment.targetHost = "192.168.23.14";
  deployment.targetUser = "grw";

  imports = [
      ../../../profiles/common.nix
      ../../../profiles/home.nix
      ../../../profiles/headless.nix
      ../../../profiles/uefi-boot.nix
      ../../../profiles/nas-mounts.nix
      ../../../profiles/intel-gfx.nix
      ../../../services/jellyfin.nix
    ];

  services.iperf3 = {
    enable = true;
    openFirewall = true;
  };

  boot = {
    kernelPackages = pkgs.linuxPackages_latest;
    initrd.kernelModules = [
      "bcachefs"
      "ixgbe"
      "r8169"
      "nfsv4"
    ];
  };

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
    useNetworkd = true;
    useDHCP = false;
  };

  systemd.network = {
    enable = true;
    wait-online.anyInterface = true;
    networks = {
      "10-10g" = {
        matchConfig.Driver = "ixgbe";
        networkConfig = {
          DHCP = "yes";
          IPv6AcceptRA = true;
          IPv6PrivacyExtensions = true;
          IgnoreCarrierLoss = true;
        };
        dhcpV4Config = {
          RouteMetric = 1;
          UseDNS = true;
          UseDomains = false;
          SendRelease = true;
        };
        linkConfig.RequiredForOnline = "routable";
      };
      "10-gbit" = {
        matchConfig.Driver = "r8169";
        networkConfig = {
          DHCP = "yes";
          IPv6AcceptRA = true;
          DNSOverTLS = true;
          DNSSEC = true;
          IPv6PrivacyExtensions = true;
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
    };
  };
}
