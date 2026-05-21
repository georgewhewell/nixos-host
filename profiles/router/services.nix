{
  config,
  pkgs,
  lib,
  network,
  ...
}: let
  lanName = config.router.lanInterface;
in {
  boot.initrd.kernelModules = [
    "nf_tables"
    "nft_compat"
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
    inetutils
  ];

  services.dnscrypt-proxy = {
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
      expand-hosts = true;
      server = ["127.0.0.1#54"];
      domain = network.domains.lan;
      local = "/${network.domains.lan}/";
      bind-dynamic = true;
      interface = [lanName "wg-home"];
      except-interface = "lo";
      "dhcp-range" = [
        "${lanName},${network.ipOf "lan" network.vlans.lan.dhcp.start},${network.ipOf "lan" network.vlans.lan.dhcp.end},${network.vlans.lan.dhcp.lease}"
      ];
      "dhcp-option" = [
        "${lanName},3,${network.routerIp}"
        "${lanName},option:domain-search,${network.domains.lan}"
      ];
      # Generated from network.nix hosts that have a MAC address.
      "dhcp-host" = network.toDnsmasqDhcpHost;
      # Generated from network.nix hosts (and their extraNames). Each name
      # produces bare, lan-FQDN, and public-FQDN records.
      "address" = network.toDnsmasqAddress;
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

  services.tor = {
    enable = true;
    openFirewall = true;

    client = {
      enable = true;
      transparentProxy.enable = true;
      socksListenAddress = {
        IsolateDestAddr = true;
        addr = network.routerIp;
        port = 9050;
      };
    };

    relay = {
      enable = true;
      role = "relay";
    };

    settings = {
      # ContactInfo = "toradmin@example.org";
      Nickname = "sataniclink";
      ORPort = 9999;
      ControlPort = [
        { addr = "127.0.0.1"; port = 9051; }
        { addr = network.routerIp; port = 9051; }
      ];
      HashedControlPassword = "16:C802A1E6C9360DEE6086F9C56339BAA9F4B58E9D39A20E200F7E3E336E";
      BandWidthRate = "10 MBytes";
    };
  };
}
