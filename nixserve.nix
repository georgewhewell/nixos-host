# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, lib, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./services/docker.nix
      ./users.nix
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
  boot.loader.grub.devices = ["/dev/sda" "/dev/sdb" "/dev/sdc" "/dev/sdd" "/dev/sde"];

  networking.hostName = "nixserve"; # Define your hostname.
  networking.hostId = "4e98920d";

  boot.initrd.availableKernelModules = [ "ehci_pci" "ahci" "sd_mod" ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" =
    { device = "zpool/root/nixos";
      fsType = "zfs";
    };

  swapDevices = [ ];

  nix.maxJobs = lib.mkDefault 32;

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;
  services.openssh.forwardX11 = true;

  networking.firewall.enable = true;
  networking.firewall.trustedInterfaces = [
    "docker0"
    "virbr_kub_gl"
    "virbr_kub_pods"
  ];

  # Enable the X11 windowing system.
  services.xserver.enable = false;

  virtualisation.libvirtd.enable = true;

  # The NixOS release to be compatible with for stateful data such as databases.
  system.stateVersion = "17.03";

}
