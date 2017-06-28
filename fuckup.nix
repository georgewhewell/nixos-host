# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, lib, ... }:

{
  networking.hostName = "fuckup"; # Define your hostname.
  networking.hostId = "deadbeef";

  fileSystems."/" =
    { device = "zpool/root/nixos";
      fsType = "zfs";
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

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usb_storage" "usbhid" "sd_mod" ];
  boot.kernelModules = [ "wl" "kvm-intel" ];
  boot.kernelPackages = pkgs.linuxPackages_latest;

  boot.extraModulePackages = [ config.boot.kernelPackages.broadcom_sta ];
  boot.kernelParams = ["systemd.legacy_systemd_cgroup_controller=yes"];
  boot.zfs.enableUnstable = true;

  networking.wireless = {
    enable = true;
    userControlled = true;
  };

  nix.maxJobs    = lib.mkDefault 8;
  nix.buildCores = lib.mkDefault 8;
  nix.nixPath = [
	    "nixpkgs=/etc/nixos/nixpkgs"
	    "nixos-config=/etc/nixos/configuration.nix"
  ];

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
     defaultLocale = "en_GB.UTF-8";
   };

  # Set your time zone.
  time.timeZone = "Europe/London";

  environment.systemPackages = with pkgs; [
    wget
    atom
    chromium
    wireshark
  ];

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;
  services.openssh.forwardX11 = true;

  services.avahi.enable = true;
  services.avahi.publish.enable = true;
  services.avahi.publish.addresses = true;
  services.avahi.nssmdns = true;
  services.avahi.interfaces = ["br0"];

  hardware.pulseaudio = {
    enable = true;
    extraConfig = ''
      unload-module module-switch-on-port-available
    '';
  };

  virtualisation.docker.enable = true;

  networking.bridges.br0 = {
    interfaces = [ "enp0s31f6" "enp1s0f0" "enp1s0f1"];
  };

  # The NixOS release to be compatible with for stateful data such as databases.
  system.stateVersion = "17.03";

  hardware.enableAllFirmware = true;
  hardware.bluetooth.enable = true;

  services.postgresql.enable = true;
  services.postgresql.enableTCPIP = true;
  /*services.postgresql.authentication = ''
    host  all  all 172.17.0.0/16 md5
  '';*/

  networking.firewall.allowedTCPPorts = [ 9100 ];
  systemd.services.prometheus-node-exporter = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      TimeoutStartSec = 0;
      Restart = "always";
      ExecStart = ''${pkgs.prometheus-node-exporter}/bin/node_exporter
      '';
    };
  };

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

  services.printing = {
    enable = true;
    drivers = [ pkgs.gutenprint ];
  };

  imports =
    [
      ./i3.nix
      ./users.nix
      ./services/virt/host.nix
      ./modules/custom-packages.nix
    ];
}
