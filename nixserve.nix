# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, lib, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./services/docker.nix
    ];
    sound.enable = false;
  boot.vesa = false;
boot.kernelParams = ["console=ttyS,9600n8" "console=ttyS1,9600n8"];
  boot.loader.grub.extraConfig = "serial; terminal_input serial; terminal_output serial";
  services.avahi.enable = true;
  services.avahi.publish.enable = true;
  services.avahi.publish.addresses = true;
  services.avahi.nssmdns = true;
  services.avahi.interfaces = [ "enp1s0" ];

boot.kernelPackages = pkgs.linuxPackages_latest;
  # Use the GRUB 2 boot loader.
  boot.loader.grub.enable = true;
  boot.loader.grub.version = 2;
  # boot.loader.grub.efiSupport = true;
  # boot.loader.grub.efiInstallAsRemovable = true;
  # boot.loader.efi.efiSysMountPoint = "/boot/efi";
  # Define on which hard drive you want to install Grub.
  # boot.loader.grub.device = "/dev/sda"; # or "nodev" for efi only
  boot.loader.grub.mirroredBoots = [
  { devices = [ "/dev/disk/by-id/ata-INTEL_SSDSC2BA400G3_BTTV510006PL400HGN" "/dev/disk/by-id/ata-INTEL_SSDSC2BA400G3_BTTV530601E1400HGN" ]; path="/boot"; }
  ];

  networking.hostName = "nixserve"; # Define your hostname.
  networking.hostId = "4e98920d";
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  boot.initrd.availableKernelModules = [ "ehci_pci" "ahci" "sd_mod" ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" =
    { device = "ipool/root/nixos";
      fsType = "zfs";
    };

  swapDevices = [ ];

  nix.maxJobs = lib.mkDefault 32;
  # Select internationalisation properties.
  # i18n = {
  #   consoleFont = "Lat2-Terminus16";
  #   consoleKeyMap = "us";
  #   defaultLocale = "en_US.UTF-8";
  # };

  # Set your time zone.
  # time.timeZone = "Europe/Amsterdam";

  # List packages installed in system profile. To search by name, run:
  # $ nix-env -qaP | grep wget
  # environment.systemPackages = with pkgs; [
  #   wget
  # ];

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  # Enable CUPS to print documents.
  # services.printing.enable = true;

  # Enable the X11 windowing system.
  services.xserver.enable = false;
  # services.xserver.layout = "us";
  # services.xserver.xkbOptions = "eurosign:e";

  virtualisation.libvirtd.enable = true;

  # Enable the KDE Desktop Environment.
  # services.xserver.displayManager.kdm.enable = true;
  # services.xserver.desktopManager.kde4.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  # users.extraUsers.guest = {
  #   isNormalUser = true;
  #   uid = 1000;
  # };
  users.extraUsers.grw = {
    extraGroups = ["wheel" "libvirtd" "docker"];
    isNormalUser = true;
     openssh.authorizedKeys.keys = [
      "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBBZ7a3vc5ex0sSTz8uitNrf96k5iURfRL8e9AoM93Yw1oKk5CD4mOZLOb7Av7SwFLtvgGMTnpLsxuusj2QoGTCk= grw@h9fp4whfi.local"
"ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC/yARn1J0K+z8kdhLGxZgCe0kIrCJg5o7DC0oITmbzE3YKrubFVNn7zHkwzRw0b8kjfZFIxFbo5toOFCO0VN5biujrWbutzlLjTnFP0YqoL47XD58gU+TWZb/9qoV1Yjj1OUXJ+93ZTGjXGyZ+0FDtp84lFoDgSvBXf8C742g4gm6KkXYFfGYMz8LRKSnXYpeuMu18UdZVo33m8aweTvZ+m7riD6YCJILNIPFIvVExg+UNzOh4t0Hrj+O5ir9NNCqQeu633yXKlOMShbQVmmPZfrxpg24Fv5orX/pZZM+fHB94yO5wunlzxVsF5GVjCKJL5Gj/SqCRePohDiePNdP/ grw@fuckup"
    ];
  };
 security.sudo.wheelNeedsPassword = false;

  services.openssh.forwardX11 = true;
  # The NixOS release to be compatible with for stateful data such as databases.
  system.stateVersion = "17.03";

}
