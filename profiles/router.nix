{ config, lib, pkgs, inputs, ... }:

let
  wanInterface = "enp1s0f0np0";
  vpnInterface = "wg0-vpn";
  lanBridge = "br0.lan";
in
{

  services.usbmuxd.enable = true;

  boot.initrd.kernelModules = [
    "nf_tables"
    "nft_compat"
  ];

  environment.systemPackages = with pkgs; [
    btop
    wirelesstools
    bridge-utils
    ethtool
    tcpdump
    conntrack-tools
    pciutils
  ];

  # services.igmpproxy = {
  #   enable = false;
  #   config = ''
  #     quickleave

  #     phyint ${wanInterface} upstream ratelimit 0 threshold 1
  #       altnet 77.109.128.0/19
  #       altnet 224.0.0.0/8
  #       altnet 239.0.0.0/8

  #     phyint ${lanBridge} downstream ratelimit 0 threshold 1
  #       altnet 192.168.23.0/24
  #   '';
  # };

  boot.kernel.sysctl = {
    "net.ipv4.conf.all.forwarding" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
    # "net.ipv4.tcp_congestion_control" = "bbr";
    # "net.core.default_qdisc" = "fq_codel";
    # "net.ipv6.conf.all.accept_ra" = 1;
    # "net.ipv6.conf.all.request_prefix" = 1;
    # "net.ipv6.conf.all.autoconf" = 1;
    # "net.ipv6.conf.all.use_tempaddr" = 0;
  };

  systemd.services."systemd-networkd-wait-online" = {
    serviceConfig.ExecStart = [
      "" # Clear the existing ExecStart
      "${pkgs.systemd}/lib/systemd/systemd-networkd-wait-online --interface=${lanBridge}"
    ];
  };

  systemd.network =
    let
      extraLinkConfig = {
        # ReceiveChecksumOffload = "yes";
        # TransmitChecksumOffload = true;
        # TCPSegmentationOffload = true;
        # GenericSegmentationOffload = true;
        # GenericReceiveOffload = true;
        # LargeReceiveOffload = true;
      };
    in
    {
      wait-online.enable = false;
      netdevs = {
        "20-${lanBridge}" = {
          netdevConfig = {
            Kind = "bridge";
            Name = lanBridge;
          };
        };
      };
      networks = {
        "10-${lanBridge}" = {
          matchConfig.Name = lanBridge;
          bridgeConfig = { };
          address = [
            "192.168.23.1/24"
          ];
          networkConfig = {
            ConfigureWithoutCarrier = true;
            IPv6AcceptRA = false;
            IPv6SendRA = true;
          };
          # dhcpPrefixDelegationConfig = {
          #   SubnetId = "auto";
          #   Announce = true;
          # };
          # ipv6SendRAConfig = {
          #   RouterLifetimeSec = 1800;
          #   EmitDNS = false;
          #   # DNS = "fd42:23:42:b864::1";
          #   EmitDomains = false;
          #   # Domains = [
          #   #   "lan.lossy.network"
          #   # ];
          # };
          linkConfig.RequiredForOnline = "yes";
        };
        "20-lan-25g" = {
          matchConfig.Name = "enp1s0f1np1";
          networkConfig = {
            Bridge = lanBridge;
            IPv6AcceptRA = false;
            IPv6SendRA = true;
          };
          dhcpPrefixDelegationConfig = {
            SubnetId = "auto";
            Announce = true;
          };
          ipv6SendRAConfig = {
            RouterLifetimeSec = 1800;
            EmitDNS = false;
            # DNS = "fd42:23:42:b864::1";
            EmitDomains = false;
            # Domains = [
            #   "lan.lossy.network"
            # ];
          };
          linkConfig = {
            RequiredForOnline = "enslaved";
          } // extraLinkConfig;
        };
        "20-lan-2-5g" = {
          matchConfig.Driver = "igc";
          networkConfig.Bridge = lanBridge;
          linkConfig = {
            RequiredForOnline = "enslaved";
          } // extraLinkConfig;
        };
        "20-${wanInterface}" = {
          matchConfig.Name = wanInterface;
          networkConfig = {
            # start a DHCP Client for IPv4 Addressing/Routing
            DHCP = true;
            # accept Router Advertisements for Stateless IPv6 Autoconfiguraton (SLAAC)
            IPv6AcceptRA = true;
            DNSOverTLS = true;
            DNSSEC = true;
            # IPv6PrivacyExtensions = false;
            IPForward = true;
            IgnoreCarrierLoss = true;
          };
          dhcpV4Config = {
            UseDNS = false;
            UseDomains = false;

            # Don't release IPv4 address on restart/reboots to avoid churn.
            SendRelease = false;
          };
          dhcpV6Config = {
            WithoutRA = "solicit";
            PrefixDelegationHint = "::/56";
          };
          ipv6SendRAConfig = {
            Managed = true;
          };
          # make routing on this interface a dependency for network-online.target
          linkConfig = {
            RequiredForOnline = "routable";
          } // extraLinkConfig;
        };
      };
    };

  users.extraUsers.sf = {
    extraGroups = [ ];
    isNormalUser = true;
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDsEs4RIxouNDuknNbiCyGet2xQ/v74eqUmtYILlsDc3XToJqo3S/0bjiwSFUViyns1jecn943tjVEKmsMA0aKjp2KM4lu1fwBD6z3c81H+oPFCmOyFCAierxjNsgSmr9VbZechVF8a5Tk24/kvbkbNysS5k+PpabepJxvE0Zx1Idp95Yw/8jLhYqzIU28MasYdSmGCBXyEJG4LRQmfR0GAsOOsmGTWQ8MT7WIkK0UatOVOG2TKdRvfuHKlKp/ioyByk0DYFeAKbJKI1hdl3Kn2ESArC2duOznrdvIPRgC32U9F9jOWDrl47kgkwJ9Eog3j3VG5vSLdxmLVi9lYs9HTro16K8z+9E85fG30aIYCtd5JgsWUBBI1M6sqNgCfHSECFJeVv/R+fdVWNmxMzb7PbL8GHIJwHuH1LT2LSoU+VycF4DkqNO6MzRuoeQfXmCdfRW+HjWVZQCs0D4YYQCvB6HfTuErRHrBYnvHDS39HWuuYvPDga3X+QlfZYFYUyCW7zZGf0soquSmo0BN2cQOW0Zj3Kq5+CrIisWQhJGwkN+mTkqF5u692ZSyAgo1Ae7npCc0ATf/42ZQrmgCw+BLIDNMwX/X5FN5gxugRNolgcLIgP8dDjesqmQIBka8R2IJx/lSNCuMjP+JNahDVsNW/9o9Mw+wL2UnSv3axQAkN1Q== sf@chaminade"
    ];
  };

  networking = {
    enableIPv6 = true;
    useNetworkd = true;
    useDHCP = false;

    # # No local firewall.
    # nat.enable = false;
    # firewall.enable = false;

    # # flags offload;
    # # ip protocol { tcp, udp } flow offload @f
    # nftables = {
    #   enable = true;
    #   checkRuleset = false;
    #   ruleset = ''
    #     table inet filter {
    #        flowtable f {
    #          hook ingress priority 0;
    #          devices = { ${wanInterface}, enp133s0f0np0 }; 
    #        }

    #       chain input {
    #         type filter hook input priority 0; policy drop;

    #         iifname { "${lanBridge}" } accept comment "Allow local network to access the router"
    #         iifname "${wanInterface}" ct state { established, related } accept comment "Allow established traffic"
    #         iifname "${wanInterface}" icmp type { echo-request, destination-unreachable, time-exceeded } counter accept comment "Allow select ICMP"
    #         iifname "${wanInterface}" counter drop comment "Drop all other unsolicited traffic from wan"
    #         iifname "lo" accept comment "Accept everything from loopback interface"
    #       }

    #       chain forward {
    #         type filter hook forward priority filter; policy drop;

    #         iifname { "${lanBridge}" } oifname { "${wanInterface}" } accept comment "Allow trusted LAN to WAN"
    #         iifname { "${wanInterface}" } oifname { "${lanBridge}" } ct state established, related accept comment "Allow established back to LANs"
    #       }
    #     }

    #     table ip nat {
    #       chain prerouting {
    #         type nat hook prerouting priority filter; policy accept;
    #       }

    #       chain postrouting {
    #         type nat hook postrouting priority 100; policy accept;
    #         oifname "${wanInterface}" masquerade
    #       } 
    #     }
    #   '';
    # };

    domain = "lan";
    nameservers = [ "192.168.23.5" ];

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

        { sourcePort = 32400; destination = "192.168.23.5:8776"; } /* radicle */
        { sourcePort = 8333; destination = "192.168.23.5:8333"; } /* bitcoind */
      ];
    };

    # dhcpcd = {
    #   enable = true;
    #   allowInterfaces = [ wanInterface ];
    #   # extraConfig = ''
    #   #   interface ${wanInterface}
    #   #     ia_na 1
    #   #     ia_pd 1 ${lanBridge}/1/64
    #   # '';
    # };

    firewall = {
      enable = true;
      checkReversePath = false;
      trustedInterfaces = [ lanBridge ];
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
    # };
    # services.radvd =
    #   {
    #     enable = true;
    #     config = ''
    #       interface br0.lan {
    #         AdvSendAdvert on;
    #         MinRtrAdvInterval 600;
    #         MaxRtrAdvInterval 900;
    #         prefix ::/64
    #         {
    #           AdvOnLink on;
    #           AdvAutonomous on;
    #           AdvRouterAddr on;
    #         };	
    #       };
    #     '';
    #   };
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
  };

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

  # services.miniupnpd = {
  #   enable = true;
  #   externalInterface = wanInterface;
  #   internalIPs = [ lanBridge ];
  #   natpmp = true;
  #   upnp = true;
  # };

  services.avahi = {
    enable = true;
    reflector = true;
    interfaces = [
      lanBridge
    ];
  };


  # services.fail2ban = {
  #   enable = true;
  #   jails.sshd-ddos =
  #     ''
  #       filter = sshd-ddos
  #       maxretry = 2
  #       action   = iptables[name=ssh, port=ssh, protocol=tcp]
  #       enabled  = true
  #     '';
  # };

  # services.prometheus.exporters = {
  #   dnsmasq.enable = true;
  # };
}

