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
    { device = "zpool/root/nixos";
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

  nix.maxJobs = lib.mkDefault 8;
  powerManagement.cpuFreqGovernor = "performance";

  networking = {
    hostName = "fuckup";
    hostId = "deadbeef";
    useDHCP = true;
    useNetworkd = true;

    firewall = {
      enable = true;
      allowedTCPPorts = [ 9100 ];
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
        Option "Rotate" "right"
        Option "Broadcast RGB" "Full"
        ''; }
      { output = "DP-1"; primary = true; monitorConfig = ''
        Option "Broadcast RGB" "Full"
    '';}
    ];
  };

  nix.distributedBuilds = true;
  nix.buildMachines = [
    {
     hostName = "odroidxu4.4a";
     sshUser = "root";
     sshKey = "/etc/nix/buildfarm";
     system = "armv7l-linux";
     maxJobs = 2;
     supportedFeatures = [ "big-parallel" ];
    }
    {
     hostName = "rock64.4a";
     sshUser = "root";
     sshKey = "/etc/nix/buildfarm";
     system = "aarch64-linux";
     maxJobs = 2;
     supportedFeatures = [ "big-parallel" ];
    }
    ];
}
