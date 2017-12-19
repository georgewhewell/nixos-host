{ config, lib, pkgs, ... }:

{
  imports =
    [
      ./profiles/common.nix
      ./profiles/home.nix
      ./profiles/uefi-boot.nix
    ];

  services.haveged.enable = true;
  services.vnstat.enable = true;
  services.fail2ban.enable = true;
  services.fail2ban.jails.ssh-iptables = "enabled = true";
  services.thermald.enable = true;

  nix.maxJobs = lib.mkDefault 4;
  powerManagement.cpuFreqGovernor = "performance";

  environment.systemPackages = with pkgs; [
    mosh
  ];

  fileSystems."/" =
    { device = "/dev/disk/by-uuid/dd3984c7-ebec-4e35-91dc-2e176ed8e788";
      fsType = "btrfs";
    };

  fileSystems."/boot" =
    { device = "/dev/disk/by-uuid/DBE8-FF96";
      fsType = "vfat";
    };

  networking = {
    hostName = "router"; # Define your hostname.
    hostId = "deadbeef";
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
        { sourcePort = 80; destination = "192.168.23.133:80"; }
        { sourcePort = 443; destination = "192.168.23.133:443"; }
        { sourcePort = 2222; destination = "192.168.23.133:2222"; }
        { sourcePort = 51413; destination = "192.168.23.133:51413"; }
      ];
    };

    firewall = {
      enable = true;
      checkReversePath = false;
      trustedInterfaces = [ "enp3s0" ];
    };

    interfaces = {
      # Use DHCP to aquire IP from modem
      enp1s0 = {
        useDHCP = true;
      };

      # Static IP on LAN
      enp3s0 = {
        ipAddress = "192.168.23.1";
        prefixLength = 24;
      };
    };

  };

   services.avahi.interfaces = [ "enp3s0" ];
   services.dnsmasq = {
    enable = true;
    resolveLocalQueries = true;
    servers = [ "8.8.8.8" "8.8.4.4" ];
    extraConfig = ''
      domain-needed
      bogus-priv
      no-resolv
      domain=4a
      interface=lo
      interface=enp3s0
      dhcp-range=192.168.23.10,192.168.23.254,24h
      address=/router.4a/192.168.23.1
      cname=hydra.satanic.link,nixhost.4a
      cname=grafana.satanic.link,nixhost.4a
      cname=git.satanic.link,nixhost.4a
      cname=elk.satanic.link,nixhost.4a
      cname=es.satanic.link,nixhost.4a
      log-dhcp
    '';

  };

}
