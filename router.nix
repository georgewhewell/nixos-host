{ config, lib, pkgs, ... }:

{
  imports = [
    ./containers/unifi.nix
    ./profiles/common.nix
    ./profiles/home.nix
    ./profiles/uefi-boot.nix
    ./modules/traffic-shaping.nix
  ];

  services.haveged.enable = true;
  services.vnstat.enable = true;
  services.thermald.enable = true;

  nix.maxJobs = lib.mkDefault 4;
  powerManagement.cpuFreqGovernor = "ondemand";

  environment.systemPackages = with pkgs; [
    mosh
  ];

  fileSystems."/boot" =
    { device = "/dev/sda1";
      fsType = "vfat";
    };

  fileSystems."/" =
    { device = "/dev/sda2";
      fsType = "f2fs";
    };

  networking = {
    hostName = "router.lan";
    hostId = "deadbeef";
    enableIPv6 = false;

    bridges."br.lan" = {
      interfaces = [
        "enp3s0"  # port 2
      ];
    };

    nameservers = [ "127.0.0.1" ];
    nat = {
      enable = true;
      internalIPs = [
        "192.168.23.0/24"
        "192.168.24.0/24"
        "192.168.25.0/24"
      ];
      internalInterfaces = [ "br.lan" "tun0" ];
      externalInterface = "enp1s0";  # port 1
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
      trustedInterfaces = [ "br.lan" ];
      allowedUDPPorts = [ 1194 ];
    };

    interfaces = {
      # Use DHCP to acquire IP from modem
      enp1s0 = {
        useDHCP = true;
      };

      # Static IP on LAN
      "br.lan".ipv4.addresses = [{
        address = "192.168.23.1";
        prefixLength = 24;
      }];
    };

    trafficShaping = {
      enable = true;
      wanInterface = "enp1s0";
      lanInterface = "br.lan";
      lanNetwork = "192.168.23.0/24";
      maxDown = "50mbit";
      maxUp = "3mbit";
    };
  };

   boot.kernelModules = [ "tcp_bbr" ];
   boot.kernel.sysctl = {
     "net.ipv4.tcp_congestion_control" = "bbr";
     "net.core.default_qdisc" = "fq_codel";
   };

   services.avahi.interfaces = [ "br.lan" ];
   services.dnsmasq = {
    enable = true;
    resolveLocalQueries = true;
    servers = [ "8.8.8.8" "8.8.4.4" ];
    extraConfig = ''
      domain-needed
      bogus-priv
      no-resolv
      log-dhcp
      domain=lan
      interface=lo
      interface=br.lan
      dhcp-range=192.168.23.10,192.168.23.254,1h
      dhcp-host=e4:8d:8c:a8:de:40,192.168.23.2  # switch
      dhcp-host=80:2a:a8:80:96:ef,192.168.23.3  # ap
      dhcp-host=0c:c4:7a:89:fb:37,192.168.23.4  # ipmi
      dhcp-host=0c:c4:7a:87:b9:d8,192.168.23.5  # nixhost

      # hosted names
      address=/router.lan/192.168.23.1
      address=/nixhost.lan/192.168.23.5
      cname=hydra.satanic.link,nixhost.lan
      cname=grafana.satanic.link,nixhost.lan
      cname=git.satanic.link,nixhost.lan
      cname=elk.satanic.link,nixhost.lan
      cname=es.satanic.link,nixhost.lan
      cname=cache.satanic.link,nixhost.lan
    '';

  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
  };

}
