{ config, lib, pkgs, ... }:

{
  imports =
    [ 
      # Include the results of the hardware scan.
      ./users.nix
      ./nixos/17_03.nix
    ];

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = true;
    "net.ipv6.conf.all.forwarding" = true;
    "net.ipv4.conf.all.proxy_arp" = true;
  };

  hardware.enableAllFirmware = true;
  hardware.cpu.intel.updateMicrocode = true;

  nixpkgs.config = {
    allowUnfree = true;
  };

  services.vnstat = {
    enable = true;
  };

  networking = {
    hostName = "router"; # Define your hostname.
    useNetworkd = true;

    nameservers = [ "127.0.0.1" ];
    nat = {
      enable = true;
      internalIPs = [
        "192.168.23.0/24"
        "192.168.24.0/24"
        "192.168.25.0/24"
      ];
      internalInterfaces = [ "enp3s0" ];
      externalInterface = "enp1s0";
      forwardPorts = [
        { sourcePort = 80; destination = "192.168.23.175:80"; }
        { sourcePort = 443; destination = "192.168.23.175:443"; }
      ];
    };

    firewall = {
      enable = true;
      checkReversePath = false;
      trustedInterfaces = [ "enp3s0" ];
    };

    interfaces.enp1s0 = {
      useDHCP = true;
    };

    interfaces.enp3s0 = {
      ipAddress = "192.168.23.1";
      prefixLength = 24;
    };

  };

   services.dnsmasq = {
    enable = true;
    servers = [ "8.8.8.8" "8.8.4.4" ];
    extraConfig = ''
      domain-needed
      bogus-priv
      no-resolv
      domain=4a
      interface=lo
      interface=enp3s0
      dhcp-range=192.168.23.10,192.168.23.254,24h
      dhcp-range=192.168.24.10,192.168.24.254,24h
      dhcp-range=192.168.25.10,192.168.35.254,24h
      cname=hydra.satanic.link,nixhost.4a
      cname=grafana.satanic.link,nixhost.4a
      cname=git.satanic.link,nixhost.4a
      log-dhcp
    '';

  };

  time.timeZone = "Europe/London";

  services.openssh.enable = true;
  services.openssh.permitRootLogin = "yes";

  services.haveged.enable = true;
  services.thermald.enable = true;
  services.avahi.enable = true;

  sound.enable = false;

  system.stateVersion = "18.03"; # Did you read the comment?

  boot.initrd.availableKernelModules = [ "ahci" "xhci_pci" "usb_storage" "usbhid" "sd_mod" "sdhci_acpi" "r8169" "mii" "tpm" "tpm_tis" ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  fileSystems."/" =
    { device = "/dev/disk/by-uuid/dd3984c7-ebec-4e35-91dc-2e176ed8e788";
      fsType = "btrfs";
    };

  fileSystems."/boot" =
    { device = "/dev/disk/by-uuid/DBE8-FF96";
      fsType = "vfat";
    };

  swapDevices = [ ];

  nix.maxJobs = lib.mkDefault 4;
  powerManagement.cpuFreqGovernor = "performance";

  systemd.services.prometheus-node-exporter = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      TimeoutStartSec = 0;
      Restart = "always";
      ExecStart = ''${pkgs.prometheus-node-exporter}/bin/node_exporter'';
    };
  };

}
