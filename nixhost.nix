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

  networking.bridges.br0 = {
    interfaces = ["eno1" "eno2" "eno3" "eno4"];
  };

  fileSystems."/" =
    { device = "fpool/root/nixos";
      fsType = "zfs";
    };

  fileSystems."/boot" =
    { device = "/dev/disk/by-uuid/1A02-B98B";
      fsType = "vfat";
    };

  fileSystems."/var/lib/docker" =
    { device = "fpool/root/docker";
      fsType = "zfs";
    };

  swapDevices = [ ];

  nix.maxJobs = lib.mkDefault 24;

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  # Enable the X11 windowing system.
  services.xserver.enable = false;

  # autodiscover
  services.avahi.enable = true;
  services.avahi.publish.enable = true;
  services.avahi.publish.addresses = true;
  services.avahi.publish.userServices = true;
  services.avahi.nssmdns = true;
  services.avahi.interfaces = ["br0"];

  # The NixOS release to be compatible with for stateful data such as databases.
  system.stateVersion = "17.03";

  imports =
    [
      ./users.nix
      ./modules/custom-packages.nix
      ./services/unifi.nix
      ./services/nfs.nix
      ./services/grafana.nix
      ./services/prometheus.nix
      ./services/dlna.nix
      ./services/samba.nix
      ./services/transmission.nix
      ./services/docker.nix
      ./services/cardigann.nix
      ./services/couchpotato.nix
      ./services/sonarr.nix
      ./services/plex.nix
    ];
}
