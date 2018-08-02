{ config, pkgs, lib, ... }:

{
  /*
    fuckup: skylake desktop
  */

  imports =
    [
      ./profiles/common.nix
      ./profiles/development.nix
      ./profiles/bridge-interfaces.nix
      ./profiles/home.nix
      ./profiles/nas-mounts.nix
      ./profiles/uefi-boot.nix
      ./profiles/g_ether.nix
      ./profiles/xserver.nix
      ./services/docker.nix
      ./services/virt/host.nix
      ./services/virt/vfio.nix
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
  boot.blacklistedKernelModules = [
    "b44" "b43" "b43legacy" "ssb" "brcmsmac" "bcma" ];
  boot.extraModulePackages = [
    config.boot.kernelPackages.rtlwifi_new
    config.boot.kernelPackages.broadcom_sta ];

  system.stateVersion = "18.03";

  nix.maxJobs = lib.mkDefault 8;
  powerManagement.cpuFreqGovernor = "performance";

  environment.systemPackages = with pkgs; [
    steam
  ];

  users.extraUsers.root.openssh.authorizedKeys.keys = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCoqpsUUtxaO0QzI9MxCs5tRjsbORDwpjFjuUFdGHJwZqm7A2MzrRV7EKfqfolgxnyaAFs7IM9AZ7o9Lus2MWX89c4OAW0upeoj2qsXMiFZH7z50Cdmg/YMw5DtVMZwPBTl0S1COWfhw959QntlTjhcYh3usIq9b3XeTELGtJSk5RmTjPIA2LJ4cemx3Ru11SySvk0LsI3uCv0Vhy9n17g1sg5eekRs5Nvg1AJtOQcH4Du/0rUwwEDd9Zjn0YiF/uPVMVh22JzWVE5dbe81g8dw+mR6GRnN3vlYbU+JgGvMKgs2DeGvPHSJWl9rwKUVO6wuruzZH+1q2HxAr58ndz81 root@nixhost"
  ];

  networking = {
    hostName = "fuckup";
    hostId = "deadbeef";
    useDHCP = true;

    firewall = {
      enable = true;
      allowedTCPPorts = [ 9100 10809 8880 ];
      checkReversePath = false;
    };

    bridges.br0 = {
      interfaces = [
        "enp0s31f6" # onboard ethernet
        "enp1s0f0"  # sfp+
        "enp1s0f1"  # sfp+
      ];
    };
  };

  services.xserver = {
    useGlamor = true;
    videoDrivers = [ "modesetting" ];
    xrandrHeads = [
      { output = "HDMI-2"; monitorConfig = ''
        Option "Rotate" "left"
        Option "Broadcast RGB" "Full"
        ''; }
      { output = "DP-1"; primary = true; monitorConfig = ''
        # 3440x1440 @ 75.05 Hz (GTF) hsync: 112.80 kHz; pclk: 534.22 MHz
        Modeline "3440x1440_75.00"  533.87  3440 3712 4088 4736  1440 1441 1444 1503  -HSync +Vsync
        Option "PreferredMode" "3440x1440_75.00"
        Option "Broadcast RGB" "Full"
    '';}
    ];
  };

  services.redshift = {
    enable = true;
    latitude = "51.5";
    longitude = "0";

    brightness = {
      day = "1.0";
      night = "0.6";
    };
  };

  services.fwupd.enable = true;

  nix.distributedBuilds = true;
  nix.buildMachines = [
  /* { hostName = "nanopi-m3.4a";
    sshUser = "root";
    sshKey = "/etc/nix/buildfarm";
    system = "aarch64-linux";
    supportedFeatures = [ ];
    speedFactor = 2;
    maxJobs = 1;
  }
  { hostName = "amlogic.4a";
    sshUser = "root";
    sshKey = "/etc/nix/buildfarm";
    system = "aarch64-linux";
    supportedFeatures = [ "big-parallel" ];
    speedFactor = 2;
    maxJobs = 1;
  } */
  {
    hostName = "nixhost.4a";
    maxJobs = "4";
    sshUser = "root";
    sshKey = "/etc/nix/buildfarm";
    systems = ["x86_64-linux" "i686-linux" ];
    supportedFeatures = [ "kvm" "nixos-test" "big-parallel" ];
  }
  { hostName = "rock64.4a";
    sshUser = "root";
    sshKey = "/etc/nix/buildfarm";
    system = "aarch64-linux";
    supportedFeatures = [ ];
    speedFactor = 4;
    maxJobs = 1;
  }
  { hostName = "odroid-c2.4a";
    sshUser = "root";
    sshKey = "/etc/nix/buildfarm";
    system = "aarch64-linux";
    supportedFeatures = [ ];
    speedFactor = 4;
    maxJobs = 1;
  }
  { hostName = "jetson-tx1.4a";
    sshUser = "root";
    sshKey = "/etc/nix/buildfarm";
    system = "aarch64-linux";
    supportedFeatures = [ "big-parallel" ];
    speedFactor = 2;
    maxJobs = 1;
  }
  { hostName = "nanopi-m3.4a";
    sshUser = "root";
    sshKey = "/etc/nix/buildfarm";
    system = "aarch64-linux";
    supportedFeatures = [ "big-parallel" ];
    speedFactor = 3;
    maxJobs = 1;
  }
  {
    hostName = "odroidxu4.4a";
    speedFactor = 6;
    sshUser = "root";
    sshKey = "/etc/nix/buildfarm";
    system = "armv7l-linux";
    maxJobs = 1;
    supportedFeatures = [ "big-parallel" ];
  }
  { hostName = "51.15.195.104";
   speedFactor = 4;
   sshUser = "root";
   sshKey = "/etc/nix/buildfarm";
   system = "armv7l-linux";
   maxJobs = 1;
   supportedFeatures = [ "big-parallel" "highmem" ];
  }
  { hostName = "orangepi-plus2e.4a";
     speedFactor = 1;
     sshUser = "root";
     sshKey = "/etc/nix/buildfarm";
     system = "armv7l-linux";
     maxJobs = 1;
     supportedFeatures = [];
    }
  ];

  system.autoUpgrade = {
    enable = true;
    channel = https://nixos.org/channels/nixos-unstable;
    dates = "05:00";
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
  };
}
