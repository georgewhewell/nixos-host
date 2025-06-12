{pkgs, ...}: let
  lanName = "br0.lan";
in {
  boot.initrd.kernelModules = [
    "nf_tables"
    "nft_compat"
    # "i40e"
    # "ice"
  ];

  environment.systemPackages = with pkgs; [
    pciutils
    btop
    wirelesstools
    bridge-utils
    ethtool
    tcpdump
    conntrack-tools
    pciutils
    iperf
    gdb
  ];

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
    settings = {
      domain-needed = true;
      bogus-priv = true;
      no-resolv = true;
      no-hosts = true;
      log-dhcp = true;
      enable-ra = true;
      server = ["127.0.0.1#54"];
      domain = "lan.satanic.link";
      local = "/lan.satanic.link/";
      bind-dynamic = true;
      interface = lanName;
      except-interface = "lo";
      "dhcp-range" = [
        "${lanName},192.168.23.32,192.168.23.249,6h"
        "::,constructor:${lanName},ra-stateless,ra-names"
      ];
      "dhcp-option" = [
        "${lanName},3,192.168.23.1"
        "option6:23,[::]"
      ];
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
        "9c:6b:00:39:f3:91,192.168.23.14" # n100
        "9e:9c:05:57:e8:11,192.168.23.15" # arr-servers
        #
        "1c:69:20:a1:d7:9f,192.168.23.16" # zigbee stick
        "38:7A:CC:40:41:E3,192.168.23.17" # nanokvm (router)
        "00:e0:4c:68:02:e7,192.168.23.18" # rock-5b (router)
      ];
      "address" = [
        # machines
        "/router.satanic.link/192.168.23.1"
        "/mikrotik-10g.satanic.link/192.168.23.2"
        "/ap.satanic.link/192.168.23.3"
        "/x10-ipmi.satanic.link/192.168.23.4"
        "/nixhost.satanic.link/192.168.23.5"
        "/vacuum.satanic.link/192.168.23.6"
        "/trex.satanic.link/192.168.23.8"
        "/mikrotik-100g.satanic.link/192.168.23.9"
        "/trx90bmc.satanic.link/192.168.23.10"
        "/apc-ups.satanic.link/192.168.23.11"
        "/printer.satanic.link/192.168.23.12"
        "/cerberus.satanic.link/192.168.23.13"
        "/n100.satanic.link/192.168.23.14"
        "/arr-servers.satanic.link/192.168.23.15"
        "/zigbee-stick.satanic.link/192.168.23.16"
        "/nanokvm.satanic.link/192.168.23.17"
        "/rock-5b.satanic.link/192.168.23.18"
        "/poe-switch-10g.satanic.link/192.168.23.23"

        # svc
        "/jellyfin.satanic.link/192.168.23.8"
        "/grafana.satanic.link/192.168.23.8"
        "/home.satanic.link/192.168.23.8"
        "/radarr.satanic.link/192.168.23.8"
        "/sonarr.satanic.link/192.168.23.8"
        "/autobrr.satanic.link/192.168.23.8"
      ];
    };
  };

  services.avahi = {
    enable = true;
    reflector = true;
  };

  services.fail2ban.enable = true;

  services.prometheus.exporters = {
    dnsmasq.enable = true;
  };
}
