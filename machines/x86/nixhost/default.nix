{lib, ...}: {
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

  system.stateVersion = "24.11";

  deployment.targetHost = "nixhost.satanic.link";
  deployment.targetUser = "grw";

  imports = [
    ../../../profiles/common.nix
    ../../../profiles/development.nix
    ../../../profiles/headless.nix
    ../../../profiles/home.nix
    ../../../profiles/nas.nix
    ../../../profiles/uefi-boot.nix
    ../../../profiles/fastlan.nix

    ../../../services/buildfarm-slave.nix
    ../../../services/virt/host.nix
  ];

  services.tor = {
    enable = true;
    openFirewall = true;

    client = {
      enable = true;
      transparentProxy.enable = true;
      socksListenAddress = {
        IsolateDestAddr = true;
        addr = "0.0.0.0";
        port = 9050;
      };
    };

    relay = {
      enable = true;
      role = "bridge";
    };

    settings = {
      ORPort = 9999;
      ControlPort = 9051;
      SocksPolicy = ["accept *:*"];
    };
  };

  boot.zfs.requestEncryptionCredentials = false;

  services.iperf3 = {
    enable = true;
    openFirewall = true;
  };

  boot.kernelModules = [
    "ipmi_devintf"
    "ipmi_si"
  ];

  boot.supportedFilesystems = ["zfs"];
  boot.binfmt.emulatedSystems = ["aarch64-linux" "armv7l-linux"];
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
