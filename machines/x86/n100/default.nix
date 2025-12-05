{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  /*
  asrock n100 itx board
  */
  sconfig = {
    profile = "server";
    home-manager.enable = true;
    xmrig = {
      enable = true;
      package = pkgs.xmrig-alderlake;
    };
  };

  system.stateVersion = "24.11";

  deployment.targetHost = "192.168.23.14";
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

  # Enable 1GB huge pages for xmrig
  # boot.kernelParams = [
  #   "hugepagesz=1G"
  #   "hugepages=2"
  #   "default_hugepagesz=1G"
  # ];

  boot.kernel.sysctl = {
    "vm.nr_hugepages_1gb" = 2;
  };

  fileSystems."/" = {
    device = "UUID=8b8990d8-15a7-4308-a51c-4e5b7a6898e1";
    fsType = "bcachefs";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/2A3E-BFEC";
    fsType = "vfat";
    options = ["fmask=0022" "dmask=0022"];
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
          "192.168.23.14/24"
        ];
        routes = [
          {
            Gateway = "192.168.23.1";
            Metric = 1;
          }
        ];
      };
    };
  };
}
