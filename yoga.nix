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
      ./i3.nix
      ./users.nix
      ./nixos/17_03.nix
      ./services/usbmuxd.nix
    ];
}
