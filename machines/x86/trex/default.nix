{
  config,
  pkgs,
  lib,
  ...
}: {
  /*
  trex: trx90 system
  */
  sconfig = {
    profile = "desktop";
    home-manager = {
      enable = true;
      # enableGraphical = true;
      enableVscodeServer = true;
    };
  };

  imports = [
    ../../../containers/gh-runner-hellas.nix
    ../../../containers/gh-runner-grw.nix
    ../../../profiles/common.nix
    ../../../profiles/home.nix
    ../../../profiles/development.nix
    ../../../profiles/nvidia.nix
    # ../../../profiles/llmserver.nix
    ../../../profiles/uefi-boot.nix
    ../../../profiles/nas-mounts.nix
    ../../../services/buildfarm-executor.nix
    ../../../services/buildfarm-slave.nix
    ../../../services/virt/host.nix
  ];

  deployment = {
    targetHost = "192.168.23.8";
    targetUser = "grw";
    buildOnTarget = true;
  };

  system.stateVersion = "24.11";

  boot.supportedFilesystems = ["ext4" "vfat" "xfs" "zfs"];
  boot = {
    kernelModules = [
      "ipmi_devintf"
      "ipmi_si"
    ];
    kernelParams = [
      "amd_iommu=on"
      "pci=realloc=off" # fixes: only 7 of 8 pex downstream work
      "pcie=pcie_bus_perf"
      "zswap.enabled=1"
      # "zswap.compressor=zstd"
    ];
    initrd.kernelModules = ["mlx5_core" "lm92"];
    blacklistedKernelModules = ["nouveau" "amdgpu" "i915"];
  };

  environment.systemPackages = with pkgs; [pciutils fio lm_sensors];

  services.xserver.videoDrivers = ["nvidia"];
  services.xserver.enable = true;
  boot.binfmt.emulatedSystems = [
    "aarch64-linux"
  ];

  fileSystems."/" = {
    device = "pool3d/root/trex-root";
    fsType = "zfs";
    options = ["noatime"];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/37D0-505A";
    fsType = "vfat";
    options = ["iocharset=iso8859-1" "fmask=0022" "dmask=0022"];
  };

  fileSystems."/home/grw" = {
    device = "pool3d/root/grw-home";
    fsType = "zfs";
    options = ["noatime" "nofail"];
  };

  fileSystems."/home/sf" = {
    device = "pool3d/root/home/sf";
    fsType = "zfs";
    options = ["noatime" "nofail"];
  };

  services.nfs = {
    settings = {
      nfsd.vers3 = false;
      nfsd.vers4 = true;
      nfsd."vers4.0" = false;
      nfsd."vers4.1" = false;
      nfsd."vers4.2" = true;
      nfsd.threads = 16;
    };
  };

  users.extraUsers.sf = {
    isNormalUser = true;
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDsEs4RIxouNDuknNbiCyGet2xQ/v74eqUmtYILlsDc3XToJqo3S/0bjiwSFUViyns1jecn943tjVEKmsMA0aKjp2KM4lu1fwBD6z3c81H+oPFCmOyFCAierxjNsgSmr9VbZechVF8a5Tk24/kvbkbNysS5k+PpabepJxvE0Zx1Idp95Yw/8jLhYqzIU28MasYdSmGCBXyEJG4LRQmfR0GAsOOsmGTWQ8MT7WIkK0UatOVOG2TKdRvfuHKlKp/ioyByk0DYFeAKbJKI1hdl3Kn2ESArC2duOznrdvIPRgC32U9F9jOWDrl47kgkwJ9Eog3j3VG5vSLdxmLVi9lYs9HTro16K8z+9E85fG30aIYCtd5JgsWUBBI1M6sqNgCfHSECFJeVv/R+fdVWNmxMzb7PbL8GHIJwHuH1LT2LSoU+VycF4DkqNO6MzRuoeQfXmCdfRW+HjWVZQCs0D4YYQCvB6HfTuErRHrBYnvHDS39HWuuYvPDga3X+QlfZYFYUyCW7zZGf0soquSmo0BN2cQOW0Zj3Kq5+CrIisWQhJGwkN+mTkqF5u692ZSyAgo1Ae7npCc0ATf/42ZQrmgCw+BLIDNMwX/X5FN5gxugRNolgcLIgP8dDjesqmQIBka8R2IJx/lSNCuMjP+JNahDVsNW/9o9Mw+wL2UnSv3axQAkN1Q== sf@chaminade"
    ];
    extraGroups = ["video" "docker"];
  };

  services = {
    fstrim.enable = true;
    fwupd.enable = true;
    hardware = {
      bolt.enable = true;
      openrgb.enable = true;
    };
    iperf3.enable = true;
  };

  networking = {
    hostName = "trex";
    hostId = lib.mkForce "deadbeef";
    enableIPv6 = true;
    useNetworkd = true;
    nameservers = ["192.168.23.254"];
    firewall.enable = false;
  };

  services.ollama = {
    enable = true;
    acceleration = "cuda";
    host = "0.0.0.0";
    port = 11434;
  };

  services.nix-serve = {
    enable = true;
  };

  systemd.network = let
    bridgeName = "br0";
  in {
    enable = true;
    wait-online.anyInterface = true;
    netdevs = {
      "20-${bridgeName}" = {
        netdevConfig = {
          Kind = "bridge";
          Name = bridgeName;
        };
      };
    };
    networks = {
      "99-ipheth" = {
        matchConfig.Driver = "ipheth";
        networkConfig = {
          DHCP = "ipv4";
          IPv6AcceptRA = true;
          # DNSOverTLS = true;
          # DNSSEC = true;
          IPv6PrivacyExtensions = true;
          # IPv4Forward = true;
          # IgnoreCarrierLoss = true;
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
        networkConfig.Bridge = bridgeName;
        linkConfig.RequiredForOnline = "enslaved";
      };
      "10-lan-10g" = {
        matchConfig.Driver = "i40e";
        networkConfig.Bridge = bridgeName;
        linkConfig.RequiredForOnline = "enslaved";
      };
      "10-lan-10g-2" = {
        matchConfig.Driver = "ixgbe";
        networkConfig.Bridge = bridgeName;
        linkConfig.RequiredForOnline = "enslaved";
      };
      "10-lan-25g" = {
        matchConfig.Driver = "mlx5_core";
        networkConfig.Bridge = bridgeName;
        linkConfig.RequiredForOnline = "enslaved";
      };
      "05-${bridgeName}" = {
        matchConfig.Name = bridgeName;
        bridgeConfig = {};
        address = [
          "192.168.23.8/24"
        ];
        routes = [
          {Gateway = "192.168.23.1";}
        ];
        networkConfig = {
          IPv6AcceptRA = true;
          IPv6Forwarding = true;
          IPv4Forwarding = true;
          IPv6PrivacyExtensions = true;
          ConfigureWithoutCarrier = true;
          IgnoreCarrierLoss = true;
        };
        linkConfig.RequiredForOnline = "routable";
      };
    };
  };
}
