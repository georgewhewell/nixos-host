{ config, lib, pkgs, ... }:

let
  wanInterface = "enp5s0f0np0";
  lanInterfaces = [ "eno1" "eno2" "eno3" "eno4" ];
  wlanInterface = "wlan-private";
  cloudVPNInterface = "wg0-cloud";
  swapsVPNInterface = "wg1-swaps";
  vpnInterfaces = [ cloudVPNInterface swapsVPNInterface ];
  lanBridge = "br0.lan";
in
{

  services.usbmuxd.enable = true;

  environment.systemPackages = with pkgs; [
    btop
    wirelesstools
  ];

  services.igmpproxy = {
    enable = true;
    config = ''
      quickleave
      defaultdown

      phyint ${wanInterface} upstream ratelimit 0 threshold 1
          altnet 0.0.0.0/0
      phyint ${lanBridge} downstream ratelimit 0 threshold 1
          altnet 192.168.23.0/24
    '';
  };

  networking = {
    enableIPv6 = false;

    bridges."${lanBridge}" = {
      interfaces = lanInterfaces;
    };

    domain = "lan";
    nameservers = [ "192.168.23.1" ];

    nat = {
      enable = true;
      internalIPs = [
        "192.168.23.0/24"
      ];
      internalInterfaces = [ lanBridge ];
      externalInterface = wanInterface; # port 1
      forwardPorts = [
        { sourcePort = 3074; destination = "192.168.23.92:3074"; proto = "udp"; } /* bo2 */
        { sourcePort = 3074; destination = "192.168.23.92:3074"; proto = "tcp"; } /* bo2 */
        { sourcePort = 3478; destination = "192.168.23.92:3478"; } /* bo2 */
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
            3074 # bo2
          ];
          allowedUDPPorts = [
            35947 # wireguard
            51820 # wireguard (cloud)
            51821 # wireguard (swaps)
            51413 # transmission
            30303 # geth
            3074 # bo2
            3478 # bo2
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
      # "${cloudVPNInterface}".ipv4.addresses = [{
      #   address = "192.168.24.1";
      #   prefixLength = 24;
      # }];
    };

    wireless = {
      enable = false;
    };

    # wireguard = {
    #   enable = true;
    #   interfaces = {
    #     "${cloudVPNInterface}" = {
    #       ips = [ "192.168.24.1/24" ];
    #       listenPort = 51820;
    #       privateKeyFile = "/run/keys/wg-router.secret";
    #       peers = [
    #         {
    #           publicKey = "J2PvJjxRS5hZg/t5ZJk8u0yqy6MAyhzL1wvKZC8By1Y=";
    #           endpoint = "ax101.satanic.link:51820";
    #           allowedIPs = [ "192.168.24.2/32" ];
    #           persistentKeepalive = 25;
    #         }
    #       ];
    #     };
    #   };
    # };
  };

  # wait for keys before doing any wg stuff- doesnt seem to work?
  # systemd.services."wireguard-wg0-cloud".after = [ "wg-router.secret-key.service" ];
  # systemd.services."wireguard-wg0-cloud".wants = [ "wg-router.secret-key.service" ];
  # systemd.services."wireguard-wg0-cloud".requires = [ "wg-router.secret-key.service" ];

  # systemd.services."network-addresses-wg0-cloud.service".after = [ "wg-router.secret-key.service" ];
  # systemd.services."network-addresses-wg0-cloud.service".wants = [ "wg-router.secret-key.service" ];
  # systemd.services."network-addresses-wg0-cloud.service".requires = [ "wg-router.secret-key.service" ];

  # HACK: failing wg stuff (above) will cause network setup to fail, force retries?
  # systemd.services."network-addresses-${lanBridge}".serviceConfig = {
  #   Restart = "on-failure";
  #   RestartSec = 5;
  # };
  # systemd.services."${lanBridge}-netdev".serviceConfig = {
  #   Restart = "on-failure";
  #   RestartSec = 5;
  # };
  # systemd.services.dnsmasq.serviceConfig = {
  #   Restart = "on-failure";
  #   RestartSec = 5;
  # };

  deployment.keys =
    {
      "wg-router.secret" = {
        keyCommand = [ "pass" "wg-router" ];
        destDir = "/run/keys";
        uploadAt = "pre-activation";
      };
    };

  services.dnscrypt-proxy2 = {
    enable = true;
    settings = {
      listen_addresses = [ "127.0.0.1:53" ];
      static.cloudflare = {
        stamp = "sdns://AgcAAAAAAAAABzEuMC4wLjEAEmRucy5jbG91ZGZsYXJlLmNvbQovZG5zLXF1ZXJ5";
      };
      # blacklist.blacklist_file = "${pkgs.sources.hosts-blocklists}/dnscrypt-proxy/dnscrypt-proxy.blacklist.txt";
    };
  };

  services.consul.interface = {
    advertise = lanBridge;
    bind = lanBridge;
  };

  networking.hosts = {
    "192.168.23.1" = [ "nixhost" "nixhost.lan" ];
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
      # dhcp-host=0c:c4:7a:87:b9:d8,192.168.23.5   # nixhost
      dhcp-host=78:11:dc:ec:86:ea,192.168.23.6   # vacuum
      dhcp-host=f0:99:b6:42:49:05,192.168.23.48  # phone

      # hosted names
      address=/router.lan/192.168.23.1
      address=/nixhost.lan/192.168.23.1
      address=/cloud.lan/192.168.24.2
      address=/cache.satanic.link/192.168.23.1
      address=/grafana.satanic.link/192.168.23.1
      address=/home.satanic.link/192.168.23.1
      address=/jellyfin.satanic.link/192.168.23.1
      address=/ax101.lan/192.168.24.2
    '';
  };

  services.fail2ban = {
    enable = true;
    jails.DEFAULT =
      ''
        bantime  = 3600
      '';

    jails.sshd =
      ''
        filter = sshd
        maxretry = 4
        action   = iptables[name=ssh, port=ssh, protocol=tcp]
        enabled  = true
      '';

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

  # systemd.services.public-ip-sync-google-clouddns =
  #   let
  #     gcloud-json = pkgs.writeText "credentials.json" pkgs.secrets.domain-owner-terraformer;
  #   in
  #   {
  #     environment = {
  #       CLOUDSDK_CORE_PROJECT = "domain-owner";
  #       CLOUDSDK_COMPUTE_ZONE = "eu-west-1";
  #       GCLOUD_SERVICE_ACCOUNT_KEY_FILE = gcloud-json;
  #       GCLOUD_DNS_ZONE_ID = "satanic-link";
  #     };
  #     script = ''
  #       ${pkgs.public-ip-sync-google-clouddns}/bin/public-ip-sync-google-clouddns.sh -name "satanic.link."
  #       ${pkgs.public-ip-sync-google-clouddns}/bin/public-ip-sync-google-clouddns.sh -name "*.satanic.link."
  #     '';
  #     wantedBy = [ "multi-user.target" ];
  #     serviceConfig = {
  #       Type = "oneshot";
  #       Restart = "no";
  #     };
  #   };

  # systemd.timers.public-ip-sync-google-clouddns = {
  #   partOf = [ "public-ip-sync-google-clouddns.service" ];
  #   wantedBy = [ "multi-user.target" ];
  #   timerConfig = {
  #     OnBootSec = "2min";
  #     OnUnitActiveSec = "3600";
  #   };
  # };
}
