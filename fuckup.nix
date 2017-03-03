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

  fileSystems."/mnt/Media" =
    { device = "//nixhost.4a/Media";
      fsType = "cifs";
    };

  fileSystems."/mnt/Home" =
    { device = "//nixhost.4a/Home";
      fsType = "cifs";
      options = [ "credentials=/home/grw/.smbcredentials" ];
    };

  fileSystems."/mnt/nixos" =
    { device = "//nixhost.4a/nixos";
      fsType = "cifs";
      options = [ "credentials=/home/grw/.smbcredentials" ];
    };

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usb_storage" "usbhid" "sd_mod" ];
  boot.kernelModules = [ "kvm-intel" "wl" ];
  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.extraModulePackages = [ config.boot.kernelPackages.broadcom_sta ];

  nix.maxJobs = lib.mkDefault 8;

  nixpkgs.config = {
    allowUnfree = true;
    chromium = {
     enablePepperFlash = true;
     enablePepperPDF = true;
    };
  };

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
  services.avahi.interfaces = ["enp1s0f1"];

  virtualisation.libvirtd.enable = true;

  networking.bridges.br0 = {
    interfaces = ["enp1s0f0" "enp1s0f1"];
  };

  # The NixOS release to be compatible with for stateful data such as databases.
  system.stateVersion = "16.09";

  systemd.services.igfx-fullrange = {
    wantedBy = [ "multi-user.target" ];
    after = [ "graphical-session.target" ];
    requires = [ "graphical-session.target" ];
    environment = {
      DISPLAY = ":0";
      XAUTHORITY = "/home/grw/.Xauthority";
    };
    serviceConfig = {
      Type = "oneshot";
      ExecStart = ''${pkgs.xorg.xrandr}/bin/xrandr --output DP-1 --set "Broadcast RGB" "Full"
      '';
    };
  };

  systemd.services.igfx-75hz = {
    wantedBy = [ "multi-user.target" ];
    after = [ "graphical-session.target" ];
    requires = [ "graphical-session.target" ];
    environment = {
      DISPLAY = ":0";
      XAUTHORITY = "/home/grw/.Xauthority";
    };
    serviceConfig = {
      Type = "oneshot";
      ExecStart = ''${pkgs.xorg.xrandr}/bin/xrandr -r 75
      '';
    };
  };

  imports =
    [
      ./i3.nix
      ./users.nix
      ./services/docker.nix
    ];
}
