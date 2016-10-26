# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, lib, ... }:

{
  networking.hostName = "fuckup"; # Define your hostname.

  fileSystems."/" =
    { device = "/dev/disk/by-uuid/327583a9-72c6-4078-b89f-38350536a798";
      fsType = "ext4";
    };

  fileSystems."/boot" =
    { device = "/dev/disk/by-uuid/67E3-17ED";
      fsType = "vfat";
    };

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usb_storage" "usbhid" "sd_mod" ];
  boot.kernelModules = [ "kvm-intel" "wl" ];
  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.extraModulePackages = [ config.boot.kernelPackages.broadcom_sta ];

  nix.maxJobs = lib.mkDefault 8;
  nixpkgs.config.allowUnfree = true;

  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Select internationalisation properties.
   i18n = {
     consoleFont = "Lat2-Terminus16";
     consoleKeyMap = "uk";
     defaultLocale = "en_US.UTF-8";
   };

  # Set your time zone.
  time.timeZone = "Europe/London";

  environment.systemPackages = with pkgs; [
    wget
    atom
  ];

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;
  services.openssh.forwardX11 = true;

  services.avahi.enable = true;
  services.avahi.publish.enable = true;
  services.avahi.publish.addresses = true;
  services.avahi.nssmdns = true;
  services.avahi.interfaces = ["enp2s0f1"];

  virtualisation.libvirtd.enable = true;

  networking.bridges.br0 = {
    interfaces = ["enp2s0f0" "enp2s0f1" "enp0s31f6"];
  };

  # The NixOS release to be compatible with for stateful data such as databases.
  system.stateVersion = "16.09";

  imports =
    [
      ./i3.nix
      ./users.nix
      ./services/docker.nix
    ];
}
