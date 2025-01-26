{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  wanInterface = "enp1s0f0np0";
  vpnInterface = "wg0-vpn";
  lanBridge = "br0.lan";
in {
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
    iperf
  ];

  users.extraUsers.sf = {
    extraGroups = [];
    isNormalUser = true;
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDsEs4RIxouNDuknNbiCyGet2xQ/v74eqUmtYILlsDc3XToJqo3S/0bjiwSFUViyns1jecn943tjVEKmsMA0aKjp2KM4lu1fwBD6z3c81H+oPFCmOyFCAierxjNsgSmr9VbZechVF8a5Tk24/kvbkbNysS5k+PpabepJxvE0Zx1Idp95Yw/8jLhYqzIU28MasYdSmGCBXyEJG4LRQmfR0GAsOOsmGTWQ8MT7WIkK0UatOVOG2TKdRvfuHKlKp/ioyByk0DYFeAKbJKI1hdl3Kn2ESArC2duOznrdvIPRgC32U9F9jOWDrl47kgkwJ9Eog3j3VG5vSLdxmLVi9lYs9HTro16K8z+9E85fG30aIYCtd5JgsWUBBI1M6sqNgCfHSECFJeVv/R+fdVWNmxMzb7PbL8GHIJwHuH1LT2LSoU+VycF4DkqNO6MzRuoeQfXmCdfRW+HjWVZQCs0D4YYQCvB6HfTuErRHrBYnvHDS39HWuuYvPDga3X+QlfZYFYUyCW7zZGf0soquSmo0BN2cQOW0Zj3Kq5+CrIisWQhJGwkN+mTkqF5u692ZSyAgo1Ae7npCc0ATf/42ZQrmgCw+BLIDNMwX/X5FN5gxugRNolgcLIgP8dDjesqmQIBka8R2IJx/lSNCuMjP+JNahDVsNW/9o9Mw+wL2UnSv3axQAkN1Q== sf@chaminade"
    ];
  };

  systemd.services."systemd-networkd-wait-online" = {
    serviceConfig.ExecStart = [
      "" # Clear the existing ExecStart
      "${pkgs.systemd}/lib/systemd/systemd-networkd-wait-online --interface=${lanBridge}"
    ];
  };

  boot.kernel.sysctl = {
    "net.core.rmem_max" = 16777216;
    "net.core.wmem_max" = 16777216;
    "net.ipv4.tcp_rmem" = "4096 87380 16777216";
    "net.ipv4.tcp_wmem" = "4096 65536 16777216";
    "net.ipv4.tcp_congestion_control" = "bbr";
    "net.netfilter.nf_conntrack_max" = 131072;
    "net.nf_conntrack_max" = 131072;
    "net.ipv6.conf.all.forwarding" = true;

    "net.core.netdev_max_backlog" = "5000";
    "net.ipv4.route.max_size" = "524288";
    "net.ipv4.tcp_fastopen" = "3";
  };

  systemd.network = {
    wait-online.enable = false;
    netdevs = {
      "20-${lanBridge}" = {
        netdevConfig = {
          Kind = "bridge";
          Name = lanBridge;
        };
      };
    };
    links = {
      "20-${wanInterface}" = {
        matchConfig.Driver = "mlx5_core";
        linkConfig = {
          ReceiveQueues = 16;
          TransmitQueues = 16;
          RxBufferSize = 16384;
          TxBufferSize = 16384;
        };
      };
    };
    networks = {
      "10-${lanBridge}" = {
        matchConfig.Name = lanBridge;
        bridgeConfig = {};
        address = [
          "192.168.23.1/24"
        ];
        networkConfig = {
          ConfigureWithoutCarrier = true;
          DHCPPrefixDelegation = true;
          IPv6AcceptRA = false;
          IPv6SendRA = true;
          IPv6Forwarding = true;
          IPv6PrivacyExtensions = true;
        };
        dhcpPrefixDelegationConfig = {
          SubnetId = "auto";
          Announce = true;
        };
        ipv6SendRAConfig = {
          RouterLifetimeSec = 300;
          Managed = true;
        };
        linkConfig.RequiredForOnline = "routable";
      };
      "20-lan-25g" = {
        matchConfig.Name = "enp1s0f1np1";
        networkConfig.Bridge = lanBridge;
        linkConfig.RequiredForOnline = "enslaved";
      };
      "20-lan-2-5g" = {
        matchConfig.Driver = "igc";
        networkConfig.Bridge = lanBridge;
        linkConfig.RequiredForOnline = "enslaved";
      };
      "20-${wanInterface}" = {
        matchConfig.Name = wanInterface;
        networkConfig = {
          DHCP = "yes";
          IPv6AcceptRA = true;
          IPv6PrivacyExtensions = false;
          IPv6Forwarding = true;
          IgnoreCarrierLoss = true;
        };
        dhcpV4Config = {
          UseDNS = false;
          UseDomains = false;
          SendRelease = false;
        };
        dhcpV6Config = {
          WithoutRA = "solicit";
          PrefixDelegationHint = "::/56";
        };
        ipv6SendRAConfig = {
          Managed = true;
        };
        linkConfig.RequiredForOnline = "routable";
      };
    };
  };

  networking = {
    useDHCP = false;

    enableIPv6 = true;
    useNetworkd = true;
    nftables.enable = true;

    domain = "lan";
    nameservers = ["192.168.23.1"];

    nat = {
      enable = true;
      internalIPs = [
        "192.168.23.0/24"
        "192.168.24.0/24"
      ];
      internalInterfaces = [
        lanBridge
      ];
      externalInterface = wanInterface;
      forwardPorts = [
        {
          sourcePort = 51413;
          destination = "192.168.23.1:51413";
          proto = "tcp";
        }
        /*
        transmission
        */
        {
          sourcePort = 51413;
          destination = "192.168.23.5:51413";
          proto = "udp";
        }
        /*
        transmission
        */
        {
          sourcePort = 17026;
          destination = "192.168.23.5:17026";
          proto = "tcp";
        }
        /*
        qbittorrent
        */
        {
          sourcePort = 17026;
          destination = "192.168.23.5:17026";
          proto = "udp";
        }
        /*
        qbittorrent
        */
        {
          sourcePort = 9000;
          destination = "192.168.23.5:9000";
          proto = "tcp";
        }
        /*
        lighthouse
        */
        {
          sourcePort = 9000;
          destination = "192.168.23.5:9000";
          proto = "udp";
        }
        /*
        lighthouse
        */
        {
          sourcePort = 9001;
          destination = "192.168.23.5:9001";
          proto = "tcp";
        }
        /*
        lighthouse
        */
        {
          sourcePort = 9001;
          destination = "192.168.23.5:9001";
          proto = "udp";
        }
        /*
        lighthouse
        */
        {
          sourcePort = 9002;
          destination = "192.168.23.5:9002";
          proto = "tcp";
        }
        /*
        lighthouse
        */
        {
          sourcePort = 9002;
          destination = "192.168.23.5:9002";
          proto = "udp";
        }
        /*
        lighthouse
        */
        {
          sourcePort = 18080;
          destination = "192.168.23.5:18080";
          proto = "tcp";
        }
        /*
        monero
        */
        {
          sourcePort = 18080;
          destination = "192.168.23.5:18080";
          proto = "udp";
        }
        /*
        monero
        */
        {
          sourcePort = 30303;
          destination = "192.168.23.5:30303";
          proto = "tcp";
        }
        /*
        geth
        */
        {
          sourcePort = 30303;
          destination = "192.168.23.5:30303";
          proto = "udp";
        }
        /*
        geth
        */
        {
          sourcePort = 30304;
          destination = "192.168.23.5:30304";
          proto = "tcp";
        }
        /*
        reth
        */
        {
          sourcePort = 30304;
          destination = "192.168.23.5:30304";
          proto = "udp";
        }
        /*
        reth
        */
        {
          sourcePort = 4001;
          destination = "192.168.23.5:4001";
          proto = "tcp";
        }
        /*
        geth
        */
        {
          sourcePort = 4001;
          destination = "192.168.23.5:4001";
          proto = "udp";
        }
        /*
        geth
        */

        {
          sourcePort = 32400;
          destination = "192.168.23.5:8776";
        }
        /*
        radicle
        */
        {
          sourcePort = 8333;
          destination = "192.168.23.5:8333";
        }
        /*
        bitcoind
        */
      ];
    };

    firewall = {
      enable = true;
      checkReversePath = false;
      trustedInterfaces = [lanBridge];
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
            546 # dhcpv6 (client)
            547 # dhcpv6 (server)
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
  };

  services.dnscrypt-proxy2 = {
    enable = true;
    settings = {
      listen_addresses = ["127.0.0.1:54"];
      static.cloudflare = {
        stamp = "sdns://AgcAAAAAAAAABzEuMC4wLjEAEmRucy5jbG91ZGZsYXJlLmNvbQovZG5zLXF1ZXJ5";
      };
    };
  };

  services.dnsmasq = {
    enable = true;
    servers = ["127.0.0.1#54"];
    settings = {
      domain-needed = true;
      bogus-priv = true;
      no-resolv = true;
      no-hosts = true;
      log-dhcp = true;
      domain = "lan.satanic.link";
      local = "/lan.satanic.link/";
      bind-interfaces = true;
      interface = lanBridge;
      "dhcp-range" = "${lanBridge},192.168.23.20,192.168.23.249,6h";
      "dhcp-option" = "${lanBridge},3,192.168.23.1";

      "dhcp-host" = [
        "e4:8d:8c:a8:de:40,192.168.23.2" # 10gb switch
        "80:2a:a8:80:96:ef,192.168.23.3" # ap
        "0c:c4:7a:89:fb:37,192.168.23.4" # x10 ipmi
        "0c:c4:7a:87:b9:d8,192.168.23.5" # nixhost
        "78:11:dc:ec:86:ea,192.168.23.6" # vacuum
        "50:6b:4b:03:04:cb,192.168.23.8" # trex
        "48:A9:8A:93:42:4C,192.168.23.9" # 100gb switch
        "9c:6b:00:57:31:77,192.168.23.10" # trx90bmc
        "28:29:86:8b:3f:cb,192.168.23.11" # apc ups
        "b4:22:00:cf:18:63,192.168.23.12" # printer
        "c8:f0:9e:de:3c:2f,192.168.23.13" # cerberus
        "90:e2:ba:1a:69:d8,192.168.23.14" # jellyfin (10g)
        "fa:09:ef:0e:74:d7,192.168.23.15" # sonarr
        "fa:48:90:8d:03:d0,192.168.23.16" # radarr
        "fa:48:90:8d:03:d0,192.168.23.17" # nanokvm (router)
        "00:e0:4c:68:02:e7,192.168.23.18" # rock-5b (router)
      ];

      "address" = [
        "/router.satanic.link/192.168.23.1"
        "/nixhost.satanic.link/192.168.23.5"
        "/trex.satanic.link/192.168.23.8"
        "/jellyfin.satanic.link/192.168.23.1"
        "/grafana.satanic.link/192.168.23.1"
        "/home.satanic.link/192.168.23.1"
        "/radarr.satanic.link/192.168.23.1"
        "/sonarr.satanic.link/192.168.23.1"
        "/eth-mainnet.satanic.link/192.168.23.1"
        "/eth-mainnet-ws.satanic.link/192.168.23.1"
        "/static.satanic.link/192.168.23.1"
        "/gateway.satanic.link/192.168.23.1"
      ];
    };
  };

  services.miniupnpd = {
    enable = true;
    externalInterface = wanInterface;
    internalIPs = [lanBridge];
    natpmp = true;
    upnp = true;
  };

  services.avahi = {
    enable = true;
    reflector = true;
    interfaces = [
      lanBridge
    ];
  };

  services.fail2ban.enable = true;

  services.prometheus.exporters = {
    dnsmasq.enable = true;
  };
}
