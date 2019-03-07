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

  zramSwap.enable = true;

  nix.maxJobs = lib.mkDefault 4;
  environment.systemPackages = with pkgs; [
    steam
  ];

  services.xserver.dpi = 142;
  services.fwupd.enable = true;
  services.upower.enable = true;

  services.avahi.interfaces = [ "enp0s31f6" "wlp4s0" ];

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
    tempAc = "97";
    tempBat = "75";
    coreOffset = "-110";
    gpuOffset = "-50";
    uncoreOffset = "-60";
    analogioOffset = "-60";
  };

  home-manager.users.grw = { ... }: {
    imports = [
      ../home/common.nix
    ];
  };

  imports =
    [
      ./profiles/common.nix
      ./profiles/home.nix
      ./profiles/development.nix
      ./profiles/xserver.nix
      ./profiles/intel-gfx.nix
      ./profiles/uefi-boot.nix
      ./profiles/thinkpad.nix
      ./services/docker.nix
    ];

}
