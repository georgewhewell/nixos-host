{ config, pkgs, lib, ... }:

{
  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.availableKernelModules = [ "xhci_pci" "ehci_pci" "ahci" "nvme" "usb_storage" "usbhid" "sd_mod" ];
  boot.initrd.kernelModules = ["acpi" "thinkpad-acpi" "acpi-call"];
  boot.kernelModules = [ "kvm-intel" ];
  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.extraModulePackages = [
    config.boot.kernelPackages.acpi_call
    config.boot.kernelPackages.tp_smapi
  ];

  time.timeZone = "Europe/London";

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

  fileSystems."/mnt/Home" =
    { device = "//nixhost.4a/Home";
      fsType = "cifs";
      options = [ "nofail" "credentials=/home/grw/.smbcredentials" ];
    };

  swapDevices = [ ];

  nix.maxJobs = lib.mkDefault 4;

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;
  services.openssh.forwardX11 = true;

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

  nixpkgs.config = {
    allowUnfree = true;
    packageOverrides = super: let self = super.pkgs; in {
      super.networkmanager = super.modemmanager.overrideAttrs (old: rec {
         version = "git-master";
         src = pkgs.fetchgit {
           url = "git://anongit.freedesktop.org/NetworkManager/NetworkManager";
           rev = "eba646ec42e17aecf851d5d07144de95c5154d78";
           sha256 = "1xi3m3mhl7cymkhabj6163jdilf7fq36nm68i24dqqq6kvqqm0gs";
         };
      });
      super.modemmanager = super.modemmanager.overrideAttrs (old: rec {
         version = "master";
         src = pkgs.fetchgit {
           url = "git://anongit.freedesktop.org/ModemManager/ModemManager";
           rev = "5014cf39767a24109de945d99c6b9f4bb1b07274";
           sha256 = "1q9sshfcsl5cj1xa6gnaq58slhd7dqy9w1k2x27mw5scdpw7gbr4";
        };
      });
    };
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
    /*steam*/
  ];

  imports =
    [
      ./i3.nix
      ./users.nix
      ./nixos/17_03.nix
    ];
}
