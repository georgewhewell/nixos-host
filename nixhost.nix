{ config, pkgs, lib, ... }:

{
  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.availableKernelModules = [ "xhci_pci" "ehci_pci" "ahci" "nvme" "usb_storage" "usbhid" "sd_mod" ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.kernelPackages = pkgs.linuxPackages_4_10;
  boot.extraModulePackages = [ ];
  boot.zfs.enableUnstable = true;

  time.timeZone = "Europe/London";

  networking = {
    hostName = "nixhost";
    hostId = "deadbeef";
    useDHCP = true;
    bridges.br0 = {
      interfaces = ["eno1" "eno2" "eno3" "eno4"];
    };
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
  nixpkgs.config.allowUnfree = true;

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;
  services.openssh.forwardX11 = true;

  # Enable the X11 windowing system.
  services.xserver.enable = false;

  # autodiscover
  services.avahi.enable = true;
  services.avahi.publish.enable = true;
  services.avahi.publish.addresses = true;
  services.avahi.publish.userServices = true;
  services.avahi.publish.domain = true;
  services.avahi.nssmdns = true;
  services.avahi.interfaces = ["br0"];
  
  services.sabnzbd = {
    enable = true;
    user = "transmission";
    group = "transmission";
  };

  networking.firewall = {
    checkReversePath = false;
    trustedInterfaces = [ "cbr0" ];
    allowedTCPPorts = [ 6789 9001 8080 ];
  };

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = true;
    "net.ipv6.conf.all.forwarding" = true;
    "net.ipv4.conf.all.proxy_arp" = true;
  };
 
  virtualisation.libvirtd.enable = true;

  hardware.bluetooth.enable = true;
  hardware.enableAllFirmware = true;

  #hardware.firmware = [ pkgs.BCM20702A1 ];

  imports =
    [
      ./users.nix
      ./nixos/17_03.nix
      ./modules/custom-packages.nix
      ./containers/unifi.nix
      ./containers/couchpotato.nix
      ./containers/sonarr.nix
      ./containers/radarr.nix
      ./containers/plex.nix
      ./containers/emby.nix
      ./services/nfs.nix
      ./services/netatalk.nix
      ./services/grafana.nix
      ./services/prometheus.nix
      ./services/samba.nix
      ./services/transmission.nix
      ./services/docker.nix
    ];
}
