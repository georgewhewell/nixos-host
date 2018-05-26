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

  nix.maxJobs = lib.mkDefault 4;

  services.xserver.dpi = 142;
  services.fwupd.enable = true;
  system.nixos.stateVersion = "18.03";

  boot.blacklistedKernelModules = [ "mei_wdt" ];
  boot.loader.timeout = 1;

  hardware.undervolt = {
    enable = true;
    core = -125;
    cache = -125;
    gpu = -55;
    uncore = -70;
    analogio = -70;
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
