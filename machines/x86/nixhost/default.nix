{
  pkgs,
  lib,
  ...
}: {
  /*
  nixhost: xeon-d microserver
  */
  sconfig = {
    profile = "server";
    home-manager = {
      enable = true;
    };
    xmrig.enable = true;
  };

  system.stateVersion = "24.11";

  deployment.targetHost = "192.168.23.5";
  deployment.targetUser = "grw";

  imports = [
    ../../../profiles/common.nix
    ../../../profiles/headless.nix
    ../../../profiles/home.nix
    ../../../profiles/uefi-boot.nix
    ../../../profiles/zfs.nix
  ];

  services.iperf3 = {
    enable = true;
    openFirewall = true;
  };

  boot.kernelModules = [
    "ipmi_devintf"
    "ipmi_si"
  ];

  boot.kernelParams = ["pci=nocrs"];

  networking = {
    hostName = "nixhost";
    hostId = lib.mkForce "deadbeef";
    wireless.enable = false;
    enableIPv6 = true;
    useNetworkd = true;
    firewall = {
      enable = true;
      trustedInterfaces = ["br0.lan"];
    };
    nameservers = ["192.168.23.1"];
  };

  systemd.network = let
    bridgeName = "br0.lan";
  in {
    enable = true;
    # wait-online.anyInterface = true;
    netdevs = {
      "10-${bridgeName}" = {
        netdevConfig = {
          Kind = "bridge";
          Name = bridgeName;
        };
      };
    };
    networks = {
      "20-ixgbe" = {
        matchConfig.Driver = "ixgbe";
        networkConfig.Bridge = bridgeName;
        linkConfig.RequiredForOnline = "enslaved";
      };
      "20-gbe" = {
        matchConfig.Driver = "igb";
        networkConfig.Bridge = bridgeName;
        linkConfig.RequiredForOnline = "enslaved";
      };
      "10-${bridgeName}" = {
        matchConfig.Name = bridgeName;
        bridgeConfig = {};
        address = [
          "192.168.23.5/24"
        ];
        routes = [
          {Gateway = "192.168.23.1";}
        ];
        networkConfig = {
          ConfigureWithoutCarrier = true;
          IPv6AcceptRA = true;
          IPv6Forwarding = true;
          IPv4Forwarding = true;
          IPv6PrivacyExtensions = true;
        };
        linkConfig.RequiredForOnline = "routable";
      };
    };
  };

  fileSystems."/" = {
    device = "spool/root/nixos";
    fsType = "zfs";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/EFI";
    fsType = "vfat";
  };

  nix.settings.build-cores = lib.mkDefault 24;
}
