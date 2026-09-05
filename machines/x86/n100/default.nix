{
  config,
  pkgs,
  lib,
  inputs,
  network,
  ...
}: let
  self = network.hosts.n100;
in {
  /*
  asrock n100 itx board
  */
  sconfig = {
    profile = "server";
    home-manager.enable = true;
    impermanence = {
      enable = true;
      # First tmpfs-root cutover: mount the old bcachefs root at /persist, so
      # the existing impermanence data remains at /persist/persist.
      persistentStoragePath = "/persist/persist";
    };
    xmrig = {
      enable = true;
      package = pkgs.xmrig-alderlake;
    };
  };

  system.stateVersion = "24.11";

  deployment.targetHost = network.primaryIp self;
  deployment.targetUser = "grw";

  imports = with inputs.nixos-hardware.nixosModules; [
    common-cpu-intel
    common-gpu-intel

    ../../../profiles/common.nix
    ../../../profiles/home.nix
    ../../../profiles/headless.nix
    ../../../profiles/intel-gfx.nix
    ../../../profiles/uefi-boot.nix

    ../../../services/buildfarm-slave.nix
  ];

  services.prometheus.exporters = {
    node = {
      enable = true;
      openFirewall = lib.mkForce true;
    };
  };

  services.iperf3 = {
    enable = true;
    openFirewall = true;
  };

  # XMRig uses 1 GiB hugepages; reserve them at boot instead of trying to set
  # the non-existent vm.nr_hugepages_1gb sysctl.
  boot.kernelParams = [
    "hugepagesz=1G"
    "hugepages=3"
  ];
  # nixpkgs currently emits this unlock unit for boot-time bcachefs mounts even
  # when the filesystem is not encrypted.
  boot.initrd.systemd.services."unlock-bcachefs--".enable = false;
  boot.initrd.systemd.services."unlock-bcachefs-persist".enable = false;

  services.irqbalance.enable = lib.mkForce false;

  fileSystems."/" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [
      "mode=755"
      "size=8G"
    ];
  };

  fileSystems."/persist" = {
    device = "UUID=8b8990d8-15a7-4308-a51c-4e5b7a6898e1";
    fsType = "bcachefs";
    neededForBoot = true;
  };

  fileSystems."/nix" = {
    device = "/persist/nix";
    fsType = "none";
    options = ["bind"];
    depends = ["/persist"];
    neededForBoot = true;
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/2A3E-BFEC";
    fsType = "vfat";
    options = ["fmask=0077" "dmask=0077"];
  };

  networking = {
    hostName = "n100";
    hostId = lib.mkForce "deadbeef";
    enableIPv6 = true;
    useNetworkd = true;
    useDHCP = false;
    wireless.enable = false;
  };

  systemd.network = {
    enable = true;
    wait-online.anyInterface = true;
    netdevs = {
      "20-br-lan" = {
        netdevConfig = {
          Kind = "bridge";
          Name = "br0.lan";
        };
      };
    };

    networks = {
      "10-lan" = {
        matchConfig.Driver = "r8169";
        networkConfig = {
          Bridge = "br0.lan";
          ConfigureWithoutCarrier = true;
        };
        linkConfig.RequiredForOnline = "enslaved";
      };
      "40-br" = {
        matchConfig.Name = "br0.lan";
        networkConfig = {
          IPv6AcceptRA = true;
        };
        address = [
          (network.cidrOf "lan" self.addresses.lan)
        ];
        dns = [network.dnsIp];
        routes = [
          {
            Gateway = network.routerIp;
            Metric = 1;
          }
        ];
      };
    };
  };
}
