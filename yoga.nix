{ config, pkgs, lib, ... }:

{

  networking.hostName = "yoga";
  networking.hostId = "deadbeef";

  fileSystems."/" =
    { device = "zpool/root/yoga-nixos";
      fsType = "zfs";
    };

  fileSystems."/boot" =
    { device = "/dev/nvme0n1p3";
      fsType = "vfat";
    };

  swapDevices = [{ device = "/dev/nvme0n1p2"; }];

  zramSwap = {
    enable = true;
    numDevices = 4;
  };

  nix.maxJobs = lib.mkDefault 4;

  services.xserver.dpi = 142;
  services.fwupd.enable = true;
  services.upower.enable = true;

  boot.loader.timeout = 1;
  boot.blacklistedKernelModules = [
    "mei"
    "mei_me"
    "mei_wdt"
    "acer_wmi"
    "applesmc"
    "intel_backlight"
  ];

  hardware.undervolt = {
    enable = true;
    temp = 97;
    core = -120;
    cache = -120;
    gpu = -55;
    uncore = -70;
    analogio = -70;
  };

  systemd.user.services.als = {
    description = "ALS daemon";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.als-yoga}/bin/als-yoga";
    };
  };

  imports =
    [
      ./modules/undervolt.nix
      ./profiles/common.nix
      ./profiles/development.nix
      ./profiles/xserver.nix
      ./profiles/nas-mounts.nix
      ./profiles/uefi-boot.nix
      ./profiles/thinkpad.nix
      ./profiles/g_ether.nix
      ./services/docker.nix
    ];

}
