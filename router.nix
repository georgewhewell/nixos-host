{ config, lib, pkgs, ... }:

{
  imports =
    [
      ./profiles/common.nix
      ./profiles/home.nix
      ./profiles/uefi-boot.nix
      ./modules/traffic-shaping.nix
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
    enableIPv6 = false;

    nameservers = [ "127.0.0.1" ];
    nat = {
      enable = true;
      internalIPs = [
        "192.168.23.0/24"
        "192.168.24.0/24"
        "192.168.25.0/24"
      ];
      internalInterfaces = [ "enp3s0" "tun0" ];
      externalInterface = "enp1s0";
      forwardPorts = [
        { sourcePort = 80; destination = "192.168.23.5:80"; }
        { sourcePort = 443; destination = "192.168.23.5:443"; }
        { sourcePort = 2222; destination = "192.168.23.5:2222"; }
        { sourcePort = 51413; destination = "192.168.23.5:51413"; }
      ];
    };

    firewall = {
      enable = true;
      checkReversePath = false;
      trustedInterfaces = [ "enp3s0" ];
      allowedUDPPorts = [ 1194 ];
    };

    interfaces = {
      # Use DHCP to aquire IP from modem
      enp1s0 = {
        useDHCP = true;
      };

      # Static IP on LAN
      enp3s0.ipv4.addresses = [{
        address = "192.168.23.1";
        prefixLength = 24;
      }];
    };

    trafficShaping = {
      enable = true;
      wanInterface = "enp1s0";
      lanInterface = "enp3s0";
      lanNetwork = "192.168.23.0/24";
      maxDown = "200mbit";
      maxUp = "20mbit";
    };
  };

   boot.kernelModules = [ "tcp_bbr" ];
   boot.kernel.sysctl = {
     "net.ipv4.tcp_congestion_control" = "bbr";
     "net.core.default_qdisc" = "fq_codel";
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
      log-dhcp
      domain=4a
      interface=lo
      interface=enp3s0
      dhcp-range=192.168.23.10,192.168.23.254,1h
      dhcp-host=e4:8d:8c:a8:de:40,192.168.23.2  # switch
      dhcp-host=80:2a:a8:80:96:ef,192.168.23.3  # ap
      dhcp-host=0c:c4:7a:89:fb:37,192.168.23.4  # ipmi
      dhcp-host=7a:66:a0:7e:9b:45,192.168.23.5  # nixhost

      # hosted names
      address=/router.4a/192.168.23.1
      address=/nixhost.4a/192.168.23.5
      cname=hydra.satanic.link,nixhost.4a
      cname=grafana.satanic.link,nixhost.4a
      cname=git.satanic.link,nixhost.4a
      cname=elk.satanic.link,nixhost.4a
      cname=es.satanic.link,nixhost.4a
      cname=cache.satanic.link,nixhost.4a
    '';

  };

 services.openvpn.servers.satanic-link = {
   config = let
     dirName = "/etc/nix/openvpn/pki";
   in ''
     dev tun0
     proto udp
     port 1194
     server 192.168.24.0 255.255.255.0

     ca ${dirName}/ca.crt
     cert ${dirName}/issued/satanic-link.crt
     key ${dirName}/private/satanic-link.key
     dh ${dirName}/dh.pem
   '';
 };

  system.autoUpgrade = {
    enable = true;
    channel = https://nixos.org/channels/nixos-18.03-small;
    dates = "04:40";
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
  };

}
