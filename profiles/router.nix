{ config, lib, pkgs, ... }:
let
  wanInterface = "enp1s0";
  lanInterface = "enp3s0";
  wlanInterface = "wlan-private";
  vpnInterface = "wg0";
  lanBridge = "br0.lan";
in
{

  environment.systemPackages = with pkgs; [
    wirelesstools
  ];

  networking = {
    hostId = "deadbeef";
    enableIPv6 = false;

    bridges."${lanBridge}" = {
      interfaces = [
        lanInterface
      ];
    };

    nameservers = [ "127.0.0.1" ];
    nat = {
      enable = true;
      internalIPs = [
        "192.168.23.0/24"
        "192.168.24.0/24"
      ];
      internalInterfaces = [ lanBridge vpnInterface wlanInterface ];
      externalInterface = wanInterface; # port 1
      forwardPorts = [
        { sourcePort = 80; destination = "192.168.23.5:80"; loopbackIPs = [ "82.12.183.66" ]; }
        { sourcePort = 443; destination = "192.168.23.5:443"; loopbackIPs = [ "82.12.183.66" ]; }
        { sourcePort = 51413; destination = "192.168.23.5:51413"; proto = "udp"; }
        { sourcePort = 51413; destination = "192.168.23.5:51413"; proto = "tcp"; }
        { sourcePort = 32400; destination = "192.168.23.200:32400"; }
      ];
    };

    firewall = {
      enable = true;
      checkReversePath = false;
      trustedInterfaces = [ lanBridge vpnInterface wlanInterface ];
      logRefusedConnections = false;
      logRefusedPackets = false;
      logReversePathDrops = false;
      interfaces = {
        "${wanInterface}" = {
          allowedTCPPorts = [
            22 # ssh
            80 # http
            443 # https
            51413 # transmission
            32400 # plex
          ];
          allowedUDPPorts = [
            35947 # wireguard
            51820 # wireguard
            51413 # transmission
          ];
        };
      };
    };

    interfaces = {
      # Use DHCP to acquire IP from modem
      "${wanInterface}" = {
        useDHCP = true;
      };

      # Static IP on LAN
      "${lanBridge}".ipv4.addresses = [{
        address = "192.168.23.1";
        prefixLength = 24;
      }];
    };

    /*
    wireguard = {
      interfaces = {
        "${vpnInterface}" = {
    ips = [ "192.168.24.1/24" ];
          listenPort = 51820;
    peers = [ {
      allowedIPs = [ "192.168.24.2/32" ];
      publicKey = "RHTVwkbfc6LX/rWDr42WQR1U391wv39oqO2TPyF+cC4=";
    } ];
    privateKey = "i/noVqodxmQ3x4Qw2OZIp3Es8wilR5op4BYN2JUKXL0=";
        };
      };
    };
   */


    trafficShaping = {
      enable = true;
      wanInterface = wanInterface;
      lanInterface = "br.lan";
      lanNetwork = "192.168.23.0/24";
      maxDown = "95mbit";
      maxUp = "5mbit";
    };
  };

  services.dnscrypt-proxy2 = {
    enable = true;
    settings = {
      listen_addresses = [ "127.0.0.1:53" ];
      static.cloudflare = {
        stamp = "sdns://AgcAAAAAAAAABzEuMC4wLjEAEmRucy5jbG91ZGZsYXJlLmNvbQovZG5zLXF1ZXJ5";
      };
      blacklist.blacklist_file = "${pkgs.sources.hosts-blocklists}/dnscrypt-proxy/dnscrypt-proxy.blacklist.txt";
    };
  };

  services.consul.interface = {
    advertise = lanBridge;
    bind = lanBridge;
  };

  services.miniupnpd = {
    enable = true;
    externalInterface = wanInterface;
    internalIPs = [ lanBridge ];
    natpmp = true;
    upnp = true;
  };

  boot.kernelModules = [ "tcp_bbr" ];
  boot.kernel.sysctl = {
    "net.ipv4.tcp_congestion_control" = "bbr";
    "net.core.default_qdisc" = "fq_codel";
  };

  services.avahi.interfaces = [ lanBridge ];

  services.hostapd = {
    enable = true;
    interface = wlanInterface;
    hwMode = "a";
    channel = 165;
    ssid = "nix";
    wpa = false;
    extraConfig = ''
      bridge=${lanBridge}
    '';
  };

  services.dnsmasq = {
    enable = true;
    resolveLocalQueries = true;
    servers = [ "127.0.0.1#53" ];
    extraConfig = ''
      domain-needed
      bogus-priv
      no-resolv
      no-hosts
      log-dhcp
      domain=lan
      bind-interfaces
      except-interface=lo
      interface=${lanBridge}
      dhcp-range=${lanBridge},192.168.23.10,192.168.23.254,6h
      dhcp-host=e4:8d:8c:a8:de:40,192.168.23.2   # switch
      dhcp-host=80:2a:a8:80:96:ef,192.168.23.3   # ap
      dhcp-host=0c:c4:7a:89:fb:37,192.168.23.4   # ipmi
      dhcp-host=0c:c4:7a:87:b9:d8,192.168.23.5   # nixhost
      dhcp-host=de:18:46:58:73:da,192.168.23.200 # plex
      dhcp-host=f0:99:b6:42:49:05,192.168.23.48  # phone

      # hosted names
      address=/router.lan/192.168.23.1
      address=/nixhost.lan/192.168.23.5
      address=/cache.satanic.link/192.168.23.5
      address=/hydra.satanic.link/192.168.23.5
      cname=grafana.satanic.link,nixhost.lan
      cname=git.satanic.link,nixhost.lan
      cname=home.satanic.link,nixhost.lan
    '';
  };

}
