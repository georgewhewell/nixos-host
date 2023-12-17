{ config, lib, pkgs, ... }:

let
  wanInterface = "enp133s0f2np2";
  lanInterfaces = [ "eno1" "eno2" "eno3" "eno4" "eno5" "eno6" "enp133s0f0np0" ];
  vpnInterface = "wg0-vpn";
  # vpnInterfaces = [ vpnInterface ];
  lanBridge = "br0.lan";
in
{

  services.usbmuxd.enable = true;
  environment.systemPackages = with pkgs; [
    btop
    wirelesstools
    bridge-utils
    ethtool
    tcpdump
  ];

  services.igmpproxy = {
    enable = false;
    config = ''
      quickleave

      phyint ${wanInterface} upstream ratelimit 0 threshold 1
        altnet 77.109.128.0/19
        altnet 224.0.0.0/8
        altnet 239.0.0.0/8

      phyint ${lanBridge} downstream ratelimit 0 threshold 1
        altnet 192.168.23.0/24
    '';
  };

  boot.kernel.sysctl = {
    "net.ipv4.conf.all.forwarding" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
    # "net.ipv6.conf.all.accept_ra" = 1;
    # "net.ipv6.conf.all.request_prefix" = 1;
    # "net.ipv6.conf.all.autoconf" = 1;
    # "net.ipv6.conf.all.use_tempaddr" = 0;
  };

  networking = {
    enableIPv6 = true;

    bridges."${lanBridge}" = {
      interfaces = lanInterfaces;
    };

    domain = "lan";
    nameservers = [ "192.168.23.1" ];

    nat = {
      enable = true;
      internalIPs = [
        "192.168.23.0/24"
        "192.168.24.0/24"
      ];
      internalInterfaces = [
        lanBridge
      ];
      externalInterface = wanInterface; # port 1
      forwardPorts = [
        { sourcePort = 80; destination = "192.168.23.5:80"; proto = "tcp"; } /* nginx */
        { sourcePort = 443; destination = "192.168.23.5:443"; proto = "tcp"; } /* nginx */
        { sourcePort = 51413; destination = "192.168.23.1:51413"; proto = "tcp"; } /* transmission */
        { sourcePort = 51413; destination = "192.168.23.5:51413"; proto = "udp"; } /* transmission */
        { sourcePort = 9000; destination = "192.168.23.5:9000"; proto = "tcp"; } /* lighthouse */
        { sourcePort = 9000; destination = "192.168.23.5:9000"; proto = "udp"; } /* lighthouse */
        { sourcePort = 9001; destination = "192.168.23.5:9001"; proto = "tcp"; } /* lighthouse */
        { sourcePort = 9001; destination = "192.168.23.5:9001"; proto = "udp"; } /* lighthouse */
        { sourcePort = 9002; destination = "192.168.23.5:9002"; proto = "tcp"; } /* lighthouse */
        { sourcePort = 9002; destination = "192.168.23.5:9002"; proto = "udp"; } /* lighthouse */
        { sourcePort = 18080; destination = "192.168.23.5:18080"; proto = "tcp"; } /* monero */
        { sourcePort = 18080; destination = "192.168.23.5:18080"; proto = "udp"; } /* monero */
        { sourcePort = 30303; destination = "192.168.23.5:30303"; proto = "tcp"; } /* geth */
        { sourcePort = 30303; destination = "192.168.23.5:30303"; proto = "udp"; } /* geth */
        { sourcePort = 30304; destination = "192.168.23.5:30304"; proto = "tcp"; } /* reth */
        { sourcePort = 30304; destination = "192.168.23.5:30304"; proto = "udp"; } /* reth */
        { sourcePort = 4001; destination = "192.168.23.5:4001"; proto = "tcp"; } /* geth */
        { sourcePort = 4001; destination = "192.168.23.5:4001"; proto = "udp"; } /* geth */
      ];
    };

    dhcpcd = {
      enable = true;
      allowInterfaces = [ wanInterface ];
      extraConfig = ''
        interface ${wanInterface}
          ia_na 1
          ia_pd 1 ${lanBridge}/1/64
      '';
    };

    firewall = {
      enable = true;
      checkReversePath = false;
      trustedInterfaces = [ lanBridge ] ++ lanInterfaces;
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
            3074 # bo2

            9000 # lighthouse
            9001 # lighthouse
            9002 # lighthouse

            30303 # geth
            30304 # reth

            18080 # monero

            42069 # Snap sync (Bittorrent)
          ];
          allowedUDPPorts = [
            546 # dhcpv6 
            35947 # wireguard
            51820 # wireguard (cloud)
            51821 # wireguard (swaps)
            51413 # transmission
            3074 # bo2
            3478 # bo2

            5000 # (IPTV)

            9000 # lighthouse
            9001 # lighthouse
            9002 # lighthouse

            30303 # geth
            30304 # reth

            18080 # monero

            42069 # Snap sync (Bittorrent)
          ];
        };
      };
      # extraCommands = ''
      #   ${pkgs.iptables}/bin/
      # '';
    };

    interfaces = {
      # Use DHCP to acquire IP from modem
      "${wanInterface}" = {
        useDHCP = true;
        # proxyARP = true;
      };

      # Static IP on LAN
      "${lanBridge}".ipv4.addresses = [{
        address = "192.168.23.1";
        prefixLength = 24;
      }];

      # Static VPN IP
      # "${vpnInterface}".ipv4.addresses = [{
      #   address = "192.168.24.1";
      #   prefixLength = 24;
      # }];
    };

    wireless = {
      enable = false;
    };

    # wireguard = {
    #   enable = false;
    #   interfaces = {
    #     "${vpnInterface}" = {
    #       ips = [ "192.168.24.1/24" ];
    #       listenPort = 51820;
    #       privateKeyFile = "/run/keys/wg-router.secret";
    #       peers = [
    #         {
    #           # mac air
    #           publicKey = "T+jpoipZEmmc76Nh72NZYZF3SsngDxoBRZIWVyp5c3A=";
    #           allowedIPs = [ "192.168.24.2/32" ];
    #           persistentKeepalive = 25;
    #         }
    #         {
    #           # iphone
    #           publicKey = "tIxnCBM8di2/TmepKl/RWrit0cj/5YpEiF3hdpYBZno=";
    #           allowedIPs = [ "192.168.24.3/32" ];
    #           persistentKeepalive = 25;
    #         }
    #       ];
    #     };
    #   };
    # };
  };
  services.radvd =
    {
      enable = true;
      config = ''
        interface br0.lan {
          AdvSendAdvert on;
          MinRtrAdvInterval 600;
          MaxRtrAdvInterval 900;
          prefix ::/64
          {
            AdvOnLink on;
            AdvAutonomous on;
            AdvRouterAddr on;
          };	
        };
      '';
    };
  # services.corerad = {
  #   enable = true;
  #   settings = {
  #     debug = {
  #       address = "localhost:9430";
  #       prometheus = true; # enable prometheus metrics
  #     };
  #     interfaces = [
  #       # {
  #       #   name = wanInterface;
  #       #   monitor = true;
  #       # }
  #       {
  #         name = lanBridge;
  #         advertise = true;
  #         prefix = [
  #           { prefix = "::/64"; }
  #         ];
  #       }
  #     ];
  #   };
  # };

  # wait for keys before doing any wg stuff- doesnt seem to work?
  # systemd.services."wireguard-wg0-cloud".after = [ "wg-router.secret-key.service" ];
  # systemd.services."wireguard-wg0-cloud".wants = [ "wg-router.secret-key.service" ];
  # systemd.services."wireguard-wg0-cloud".requires = [ "wg-router.secret-key.service" ];

  # systemd.services."network-addresses-wg0-cloud.service".after = [ "wg-router.secret-key.service" ];
  # systemd.services."network-addresses-wg0-cloud.service".wants = [ "wg-router.secret-key.service" ];
  # systemd.services."network-addresses-wg0-cloud.service".requires = [ "wg-router.secret-key.service" ];

  # deployment.keys =
  #   {
  #     "wg-router.secret" = {
  #       keyCommand = [ "pass" "wg-router" ];
  #       destDir = "/run/keys";
  #       uploadAt = "pre-activation";
  #     };
  #   };

  services.dnscrypt-proxy2 = {
    enable = true;
    settings = {
      listen_addresses = [ "127.0.0.1:54" ];
      static.cloudflare = {
        stamp = "sdns://AgcAAAAAAAAABzEuMC4wLjEAEmRucy5jbG91ZGZsYXJlLmNvbQovZG5zLXF1ZXJ5";
      };
      # blacklist.blacklist_file = "${pkgs.sources.hosts-blocklists}/dnscrypt-proxy/dnscrypt-proxy.blacklist.txt";
    };
  };

  networking.hosts = {
    "192.168.23.1" = [ "router" "router.lan" ];
    "192.168.23.5" = [ "nixhost" "nixhost.lan" ];
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
    servers = [ "127.0.0.1#54" ];
    extraConfig = ''
      domain-needed
      bogus-priv
      no-resolv
      no-hosts
      log-dhcp
      domain=lan
      bind-interfaces
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
      address=/grafana.satanic.link/192.168.23.5
      address=/home.satanic.link/192.168.23.5
      address=/jellyfin.satanic.link/192.168.23.5
      address=/paperless.satanic.link/192.168.23.5
      address=/radarr.satanic.link/192.168.23.5
      address=/sonarr.satanic.link/192.168.23.5
      address=/eth-mainnet.satanic.link/192.168.23.5
      address=/eth-mainnet-ws.satanic.link/192.168.23.5
      address=/reth-mainnet.satanic.link/192.168.23.5
      address=/reth-mainnet-ws.satanic.link/192.168.23.5
    '';
  };

  services.fail2ban = {
    enable = true;
    jails.sshd-ddos =
      ''
        filter = sshd-ddos
        maxretry = 2
        action   = iptables[name=ssh, port=ssh, protocol=tcp]
        enabled  = true
      '';
  };

  services.prometheus.exporters = {
    dnsmasq.enable = true;
  };
}
