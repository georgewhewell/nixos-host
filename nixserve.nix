# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, lib, ... }:

{

  fileSystems."/" =
    { device = "zpool/root/nixos";
      fsType = "zfs";
    };

  swapDevices = [ ];

  sound.enable = false;
  boot.vesa = false;
  services.xserver.enable = false;

  boot.initrd.availableKernelModules = [ "ehci_pci" "ahci" "sd_mod" ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  boot.kernelParams = ["console=ttyS,9600n8" "console=ttyS1,9600n8"];
  boot.loader.grub.extraConfig = "serial; terminal_input serial; terminal_output serial";
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Use the GRUB 2 boot loader.
  boot.loader.grub.enable = true;
  boot.loader.grub.version = 2;
  boot.loader.grub.devices = ["/dev/sda" "/dev/sdb" "/dev/sdc" "/dev/sdd" "/dev/sde"];

  networking = {
    hostName = "nixserve";
    hostId = "4e98920d";

    defaultGateway = "185.141.204.1";
    nameservers = [
      "8.8.8.8" "8.8.4.4"
    ];

    firewall = {
      enable = true;
      trustedInterfaces = [
        "docker0"
        "virbr_kub_gl"
        "virbr_kub_pods"
      ];
    };

    interfaces = {
      enp2s0 = {
        useDHCP = false;
        ip4 = [
          { address = "185.141.204.129"; prefixLength = 24;}
          { address = "185.141.204.130"; prefixLength = 24;}
        ];
      };
    };
  };

  nix.maxJobs = lib.mkDefault 32;

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;
  services.openssh.forwardX11 = true;

  # The NixOS release to be compatible with for stateful data such as databases.
  system.stateVersion = "17.03";

  imports =
    [ # Include the results of the hardware scan.
      ./services/docker.nix
      ./users.nix
    ];
}
