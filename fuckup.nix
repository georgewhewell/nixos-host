# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, lib, ... }:

{
  fileSystems."/" =
    { device = "zpool/root/nixos";
      fsType = "zfs";
    };

  fileSystems."/boot" =
    { device = "/dev/disk/by-uuid/CD68-6C43";
      fsType = "vfat";
    };

  fileSystems."/mnt/Media" =
    { device = "//nixhost.4a/Media";
      fsType = "cifs";
      options = [ "credentials=/home/grw/.smbcredentials" ];
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

  nix.maxJobs = lib.mkDefault 8;

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
    vim
    rsync
    chromium
    #wireshark
    /*virtmanager*/
    nox
    unzip
    gitAndTools.gitFull
    htop
    xz
    steam
    psmisc
    pwgen
    tmux
    esp-open-sdk
  ];

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;
  services.openssh.forwardX11 = true;

  programs.ssh.startAgent = true;
  programs.ssh.forwardX11 = true;

  services.avahi = {
    enable = true;
    publish.enable = true;
    publish.addresses = true;
    interfaces = [ "br0" ];
  };

  hardware.pulseaudio = {
    enable = true;
    extraConfig = ''
      unload-module module-switch-on-port-available
    '';
  };

  hardware.enableAllFirmware = true;
  hardware.bluetooth.enable = true;

  services.postgresql.enable = true;
  services.postgresql.enableTCPIP = true;

  networking = {
    hostName = "fuckup";
    hostId = "deadbeef";
    useDHCP = true;

    firewall = {
      enable = true;
      allowedTCPPorts = [ 9100 ];
      checkReversePath = false;
      extraCommands = ''
        # Not strictly firewall, but..
        ${pkgs.nettools}/bin/ifconfig enp1s0f0 promisc
        ${pkgs.nettools}/bin/ifconfig enp1s0f1 promisc
        ${pkgs.nettools}/bin/ifconfig enp0s31f6 promisc
        ${pkgs.nettools}/bin/ifconfig br0 promisc
      '';
    };

    wireless = {
      enable = true;
      userControlled = true;
    };

    bridges.br0 = {
      rstp = true;
      interfaces = [ "enp0s31f6" "enp1s0f0" "enp1s0f1" ];
    };
  };

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

  services.udev.extraRules = ''
    SUBSYSTEMS=="usb", ATTRS{idVendor}=="20a0", ATTRS{idProduct}=="41ec", MODE:="0666"
  '';

  systemd.services."dbus-org.bluez".serviceConfig.ExecStart = "${pkgs.bluez}/sbin/bluetoothd -n -d --compat";

  services.printing = {
    enable = true;
    drivers = [ pkgs.gutenprint ];
  };

  imports =
    [
      ./profiles/g_ether.nix
      ./nixos/17_03.nix
      ./i3.nix
      ./users.nix
      ./services/docker.nix
      ./buildfarm.nix
      ./services/virt/host.nix
      ./services/virt/vfio.nix
      ./modules/custom-packages.nix
    ];
}
