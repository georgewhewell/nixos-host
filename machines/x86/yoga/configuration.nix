{ config, pkgs, lib, ... }:

{

  imports = [
    ../../../profiles/common.nix
    ../../../profiles/home.nix
    ../../../profiles/home-manager.nix
    ../../../profiles/nas-mounts.nix
    ../../../profiles/development.nix
    ../../../profiles/graphical.nix
    ../../../profiles/intel-gfx.nix
    ../../../profiles/uefi-boot.nix
    ../../../profiles/thinkpad.nix
    ../../../services/docker.nix
  ];

  networking.hostName = "yoga";
  networking.hostId = "deadbeef";

  virtualisation.docker.storageDriver = lib.mkForce null;

  fileSystems."/" =
    {
      device = "/dev/nvme0n1p3";
      fsType = "ext4";
    };

  fileSystems."/boot" =
    {
      device = "/dev/nvme0n1p1";
      fsType = "vfat";
    };

  swapDevices = [{ device = "/dev/nvme0n1p2"; }];

  nix.maxJobs = lib.mkDefault 4;

  console.font = lib.mkForce "${pkgs.terminus_font}/share/consolefonts/ter-u28n.psf.gz";

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
    tempAc = 95;
    tempBat = 75;
    coreOffset = -110;
    gpuOffset = -50;
    uncoreOffset = -60;
    analogioOffset = -60;
  };

}
