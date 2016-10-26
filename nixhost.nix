{ config, pkgs, lib, ... }:

{
  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.availableKernelModules = [ "xhci_pci" "ehci_pci" "ahci" "nvme" "usb_storage" "usbhid" "sd_mod" ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.extraModulePackages = [ ];

  time.timeZone = "Europe/London";

  networking.hostName = "nixhost";
  networking.hostId = "deadbeef";
  #networking.bridges.br0 = {
  #  interfaces = ["eno1" "eno2" "eno3" "eno4"];
  #};

  fileSystems."/" =
    { device = "fpool/root/nixos";
      fsType = "zfs";
    };

  fileSystems."/boot" =
    { device = "/dev/disk/by-uuid/1A02-B98B";
      fsType = "vfat";
    };

  swapDevices = [ ];

  nix.maxJobs = lib.mkDefault 24;

  # Enable the OpenSSH daemon.
   services.openssh.enable = true;

  # Enable the X11 windowing system.
  services.xserver.enable = false;

  # The NixOS release to be compatible with for stateful data such as databases.
  system.stateVersion = "17.03";

  imports =
    [
      ./users.nix
    ];
}
