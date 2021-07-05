{ config, lib, pkgs, ... }:

let
  wanInterface = "enp1s0";
  lanInterface = "enp3s0";
  wlanInterface = "wlan-private";
  cloudVPNInterface = "wg0-cloud";
  swapsVPNInterface = "wg1-swaps";
  vpnInterfaces = [ cloudVPNInterface swapsVPNInterface ];
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

    domain = "lan";
    nameservers = [ "192.168.23.1" ];

    nat = {
      enable = true;
      internalIPs = [
        "192.168.23.0/24"
      ];
      internalInterfaces = [ lanBridge wlanInterface ] ++ vpnInterfaces;
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
      trustedInterfaces = [ lanBridge wlanInterface ];
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
            30303 # geth
          ];
          allowedUDPPorts = [
            35947 # wireguard
            51820 # wireguard (cloud)
            51821 # wireguard (swaps)
            51413 # transmission
            30303 # geth
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

      # Static VPN IP
      "${cloudVPNInterface}".ipv4.addresses = [{
        address = "192.168.24.1";
        prefixLength = 24;
      }];

      # Static VPN IP
      "${swapsVPNInterface}".ipv4.addresses = [{
        address = "192.168.25.1";
        prefixLength = 24;
      }];
    };

    wireless = {
      enable = false;
    };

    wireguard = {
      enable = true;
      interfaces = {
        "${cloudVPNInterface}" = {
          ips = [ "192.168.24.1/24" ];
          listenPort = 51820;
          privateKey = pkgs.secrets.wg-router-priv;
          peers = [
            {
              publicKey = pkgs.secrets.wg-hetzner-pub;
              endpoint = "cloud.satanic.link:51820";
              allowedIPs = [ "192.168.24.2/32" ];
              persistentKeepalive = 25;
            }
            {
              publicKey = pkgs.secrets.wg-yoga-pub;
              allowedIPs = [ "192.168.24.3/32" ];
              persistentKeepalive = 25;
            }
            {
              publicKey = pkgs.secrets.wg-mobile-pub;
              allowedIPs = [ "192.168.24.6/32" ];
              persistentKeepalive = 25;
            }
          ];
        };

        "${swapsVPNInterface}" = {
          ips = [ "192.168.25.1/24" ];
          listenPort = 51821;
          privateKey = pkgs.secrets.wg-swaps-router-priv;
          peers = [
            {
              publicKey = "hweXQMD9Tl5n0jclicZrBf6bFIbRHjaQ6CQayzEkh2s=";
              endpoint = "ax101.satanic.link:51821";
              allowedIPs = [ "192.168.25.2/32" ];
              persistentKeepalive = 25;
            }
            {
              publicKey = "uZ78VPNwbGsF2nv9rqdiY1BLkQPTx7mYEO1J453z4EA=";
              endpoint = "ax41.satanic.link:51821";
              allowedIPs = [ "192.168.25.3/32" ];
              persistentKeepalive = 25;
            }
            {
              publicKey = pkgs.secrets.wg-yoga-pub;
              allowedIPs = [ "192.168.25.5/32" ];
              persistentKeepalive = 25;
            }
            {
              publicKey = pkgs.secrets.wg-mobile-pub;
              allowedIPs = [ "192.168.25.6/32" ];
              persistentKeepalive = 25;
            }
          ];
        };
      };
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

  networking.hosts = {
    "192.168.23.5" = [ "nixhost" "nixhost.lan"];
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
  services.dnsmasq = {
    enable = true;
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
      dhcp-host=78:11:dc:ec:86:ea,192.168.23.6   # vacuum
      dhcp-host=f0:99:b6:42:49:05,192.168.23.48  # phone

      # hosted names
      address=/router.lan/192.168.23.1
      address=/nixhost.lan/192.168.23.5
      address=/cloud.lan/192.168.24.2
      address=/cache.satanic.link/192.168.23.5
      address=/hydra.satanic.link/192.168.23.5
      cname=grafana.satanic.link,nixhost.lan
      cname=git.satanic.link,nixhost.lan
      cname=home.satanic.link,nixhost.lan
      cname=jupyter.satanic.link,nixhost.lan
      cname=metabase.satanic.link,nixhost.lan
      cname=sync-server.satanic.link,nixhost.lan
    '';
  };

  systemd.services.public-ip-sync-google-clouddns = let
    gcloud-json = pkgs.writeText "credentials.json" pkgs.secrets.domain-owner-terraformer;
  in {
    environment = {
      CLOUDSDK_CORE_PROJECT = "domain-owner";
      CLOUDSDK_COMPUTE_ZONE = "eu-west-1";
      GCLOUD_SERVICE_ACCOUNT_KEY_FILE = gcloud-json;
      GCLOUD_DNS_ZONE_ID = "satanic-link";
    };
    script = ''
      ${pkgs.public-ip-sync-google-clouddns}/bin/public-ip-sync-google-clouddns.sh -name "satanic.link."
      ${pkgs.public-ip-sync-google-clouddns}/bin/public-ip-sync-google-clouddns.sh -name "*.satanic.link."
    '';
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      Restart = "no";
    };
  };

  systemd.timers.public-ip-sync-google-clouddns = {
    partOf = [ "public-ip-sync-google-clouddns.service" ];
    wantedBy = [ "multi-user.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "3600";
    };
  };
}
