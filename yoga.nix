{ config, pkgs, lib, ... }:

{

  boot.initrd.kernelModules = ["acpi" "thinkpad-acpi" "acpi-call"];
  boot.extraModulePackages = [
    config.boot.kernelPackages.acpi_call
    config.boot.kernelPackages.tp_smapi
  ];

  networking.hostName = "yoga";
  networking.hostId = "deadbeef";
  networking.networkmanager.enable = true;

  fileSystems."/" =
    { device = "zpool/root/yoga-nixos";
      fsType = "zfs";
    };

  fileSystems."/boot" =
    { device = "/dev/nvme0n1p3";
      fsType = "vfat";
    };

  nix.maxJobs = lib.mkDefault 4;

  services.tlp.enable = true;

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = false;
  };

  hardware.pulseaudio = {
    enable = true;
  };

  hardware.enableAllFirmware = true;
  hardware.cpu.intel.updateMicrocode = true;
  systemd.services.ModemManager = {
    wantedBy = [ "multi-user.target" ];
  };

  environment.systemPackages = with pkgs; [
    acpi
    git
    vim
    nox
    atom
    chromium
    sway
    alacritty
    xwayland
    modemmanager
    networkmanagerapplet
    psmisc
    psutils
    usbmuxd
    gnupg
  ];

  imports =
    [
      ./profiles/common.nix
      ./profiles/home.nix
      ./profiles/nas-mounts.nix
      ./profiles/uefi-boot.nix
      ./services/usbmuxd.nix
    ];
}
