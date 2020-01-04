{ config, pkgs, lib, ... }:

{
  /*
    fuckup: skylake desktop
  */

  imports =
    [
      ../../../containers/plex.nix
      ../../../profiles/common.nix
      ../../../profiles/development.nix
      ../../../profiles/bridge-interfaces.nix
      ../../../profiles/home.nix
      ../../../profiles/home-manager.nix
      ../../../profiles/nas-mounts.nix
      ../../../profiles/uefi-boot.nix
      ../../../profiles/g_ether.nix
      ../../../profiles/graphical.nix
      ../../../services/buildfarm.nix
      ../../../services/docker.nix
      ../../../services/virt/host.nix
      ../../../services/virt/vfio.nix
    ];

  fileSystems."/" =
    { device = "zpool/root/nixos-fuckup";
      fsType = "zfs";
    };

  fileSystems."/home/grw" =
    { device = "zpool/root/grw";
      fsType = "zfs";
    };

  fileSystems."/boot" =
    { device = "/dev/disk/by-uuid/CD68-6C43";
      fsType = "vfat";
    };

  boot.kernelModules = [ "wl" ];
  boot.kernelParams = [
    "amdgpu.ppfeaturemask=0xfffd7fff"
  ];

  boot.blacklistedKernelModules = [
    "b44" "b43" "b43legacy" "ssb" "brcmsmac" "bcma" ];
  boot.extraModulePackages = [
    config.boot.kernelPackages.broadcom_sta
  ];

  nix.maxJobs = lib.mkDefault 8;
  powerManagement.cpuFreqGovernor = "performance";

  services.shairport-sync = {
    enable = true;
    arguments = "-o pa -a Airplay";
  };

  networking = {
    hostName = "fuckup";
    hostId = "deadbeef";
    wireless.enable = false;

    useDHCP = false;

    firewall = {
      enable = true;
      allowedTCPPortRanges = [ { from = 5000; to = 5005; } { from = 50000; to = 60000; } ];
      allowedUDPPortRanges = [ { from = 6000; to = 6005; } { from = 35000; to = 65535; } ];
      allowedUDPPorts = [ 5353 ];
      allowedTCPPorts = [
        9100
        10809
        8880
        8080
        /* shairport */
        3689
        5353
      ];
      checkReversePath = false;
    };

    interfaces.br0 = {
      useDHCP = true;
    };

    bridges.br0 = {
      interfaces = [
        "enp0s31f6" # onboard ethernet
        # "enp1s0f0"  # sfp+
        # "enp1s0f1"  # sfp+
      ];
    };
  };

  services.xserver = {
    useGlamor = false; # off is tearing; on is lag
    videoDrivers = [ "amdgpu" ];
    xrandrHeads = [
      { output = "DisplayPort-2"; primary = true; monitorConfig = ''
        # 3440x1440 @ 75.05 Hz (GTF) hsync: 112.80 kHz; pclk: 534.22 MHz
        Modeline "3440x1440_75.00"  533.87  3440 3712 4088 4736  1440 1441 1444 1503  -HSync +Vsync
        Option "PreferredMode" "3440x1440_75.00"
        Option "Broadcast RGB" "Full"
    '';}
    ];
  };

  virtualisation.kvmgt = {
    enable = false;
    vgpus = {
      "i915-GVTg_V5_4" = {
        uuid = "a297db4a-f4c2-11e6-90f6-d3b88d6c9525";
      };
    };
  };


  nix.distributedBuilds = true;
  nix.buildMachines = [
    {
      hostName = "/nix/store";
      supportedFeatures = [ "kvm" "nixos-test" "big-parallel" ];
      maxJobs = 4;
      systems = [ "builtin" "x86_64-linux" "i686-linux" ];
    }
    {
      hostName = "nixhost.lan";
      supportedFeatures = [ "kvm" "nixos-test" "big-parallel" ];
      maxJobs = 8;
      systems = [ "x86_64-linux" "i686-linux" ];
    }
    {
      hostName = "odroid-c2.lan";
      supportedFeatures = [];
      systems = [ "aarch64-linux" ];
    }
    {
      hostName = "yoga.lan";
      supportedFeatures = [  ];
      maxJobs = 1;
      systems = [ "x86_64-linux" "i686-linux" ];
    }
    {
      hostName = "rock64.lan";
      supportedFeatures = [];
      systems = [ "aarch64-linux" ];
    }
    {
      hostName = "nanopi-m3.lan";
      supportedFeatures = [ "big-parallel" ];
      systems = [ "aarch64-linux" ];
    }
    {
      hostName = "odroid-hc1.lan";
      speedFactor = 2;
      supportedFeatures = [ "big-parallel" ];
      systems = [ "armv7l-linux" ];
    }
    {
      hostName = "bananapi-m3.lan";
      speedFactor = 1;
      supportedFeatures = [ "big-parallel" ];
      systems = [ "armv7l-linux" ];
    }
  ];

}
