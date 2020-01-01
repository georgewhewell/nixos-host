{ config, pkgs, lib, ... }:

{

  networking.hostName = "yoga";
  networking.hostId = "deadbeef";

  fileSystems."/" =
    { device = "/dev/nvme0n1p3";
      fsType = "ext4";
    };

  fileSystems."/boot" =
    { device = "/dev/nvme0n1p1";
      fsType = "vfat";
    };

  swapDevices = [{ device = "/dev/nvme0n1p2"; }];

  nix.maxJobs = lib.mkDefault 4;

  boot.loader.timeout = 1;
  boot.blacklistedKernelModules = [
    "mei"
    "mei_me"
    "mei_wdt"
    "acer_wmi"
    "applesmc"
    "intel_backlight"
  ];

  services.undervolt = {
    enable = true;
    /* tempAc = "97"; */
    tempBat = "75";
    coreOffset = "-110";
    gpuOffset = "-50";
    uncoreOffset = "-60";
    analogioOffset = "-60";
  };

  home-manager.users.grw = { ... }: {
    imports = [ ./home/common.nix ];
  };

  imports =
    [
      ./profiles/common.nix
      ./profiles/home.nix
      ./profiles/nas-mounts.nix
      ./profiles/development.nix
      ./profiles/xserver.nix
      ./profiles/intel-gfx.nix
      ./profiles/uefi-boot.nix
      ./profiles/thinkpad.nix
      ./services/docker.nix
    ];

}
