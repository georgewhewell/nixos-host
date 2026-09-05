{
  config,
  pkgs,
  lib,
  network,
  ...
}: let
  lanName = config.router.lanInterface;
  # Wi-Fi client VLAN SVI (e.g. br0.lan.50) — DHCP/DNS served here too.
  wifiVlan = network.vlans.wifi;
  wifiName = "${lanName}.${toString wifiVlan.id}";

  # Netboot (diskless strix). The firmware HTTP clients accept the URI but
  # never issue an ARP or TCP request, so legacy PXE gets a tiny iPXE binary
  # over TFTP as a compatibility bootstrap. Everything after that remains
  # HTTP via this router; NFS/store traffic still goes directly to trex.
  netbootHosts = lib.filterAttrs (_: h: h.netboot or false) network.hosts;
  netbootMacs = h: [ h.mac ] ++ (h.extraMacs or [ ]);
  routerIp = network.routerIp;
  serviceIp = network.controlPlaneIp;
  # k3's standby resolver. It answers from the same network.nix inventory and
  # never serves DHCP, so it is safe to hand out as a second option 6 entry.
  standbyDnsIp = network.primaryIp network.hosts.k3;
  trexIp = network.primaryIp network.hosts.trex;
  netbootBaseUrl = "http://${serviceIp}/strix-netboot";
  netbootIpxeUrl = "${netbootBaseUrl}/ipxe/snponly.efi";

  netbootIpxe = pkgs.ipxe.override {
    additionalTargets = { "bin-x86_64-efi/snponly.efi" = null; };
    embedScript =
      let
        chainUrl = "${netbootBaseUrl}/by-mac/\${net0/mac}.ipxe";
      in
      pkgs.writeText "strix-router-embed.ipxe" ''
        #!ipxe
        dhcp || exit
        chain ${chainUrl} ||
        sleep 3
        chain ${chainUrl} ||
        sleep 3
        chain ${chainUrl} ||
        exit
      '';
  };

  netbootByMac = pkgs.linkFarm "strix-router-netboot-by-mac" (
    lib.concatLists (
      lib.mapAttrsToList
        (
          name: h:
            map
              (mac: {
                name = "${mac}.ipxe";
                path = pkgs.writeText "router-chain-${name}-${mac}.ipxe" ''
                  #!ipxe
                  chain ${netbootBaseUrl}/hosts/${name}/netboot.ipxe
                '';
              })
              (netbootMacs h)
        )
        netbootHosts
    )
  );

  netbootTftpRoot = pkgs.runCommand "strix-router-netboot-tftp-root" { } ''
    mkdir -p "$out"
    cp ${netbootIpxe}/snponly.efi "$out/snponly.efi"
  '';
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
      interface = [lanName wifiName "wg-home"];
      except-interface = "lo";
      "dhcp-range" = [
        "${lanName},${network.ipOf "lan" network.vlans.lan.dhcp.start},${network.ipOf "lan" network.vlans.lan.dhcp.end},${network.vlans.lan.dhcp.lease}"
        "${wifiName},${network.ipOf "wifi" wifiVlan.dhcp.start},${network.ipOf "wifi" wifiVlan.dhcp.end},${wifiVlan.dhcp.lease}"
      ];
      "dhcp-option" = [
        "${lanName},3,${network.routerIp}"
        # Two resolvers, not one. This host was a single point of failure for
        # every name in the house; k3 serves the same records from the same
        # inventory and sits on the flat LAN, so LAN clients still resolve by
        # direct L2 even when the gateway itself is the thing that died.
        "${lanName},6,${network.dnsIp},${standbyDnsIp}"
        "${lanName},option:domain-search,${network.domains.lan}"
        "${wifiName},3,${network.gatewayIp "wifi"}"
        # WiFi clients reach the standby only while routing still works, which
        # covers this host failing but not the gateway failing. Worth having.
        "${wifiName},6,${network.dnsIp},${standbyDnsIp}"
        "${wifiName},option:domain-search,${network.domains.lan}"
      ];
      # Netboot is restricted to the four tagged Strix MACs. Native UEFI HTTP
      # clients retain the URI offer; the firmware's earlier PXE attempt gets
      # snponly.efi over TFTP and iPXE immediately switches back to HTTP.
      "dhcp-mac" = lib.concatLists (
        lib.mapAttrsToList
          (_: h: map (mac: "set:netboot,${mac}") (netbootMacs h))
          netbootHosts
      );
      "dhcp-vendorclass" = [ "set:httpboot,HTTPClient" ];
      enable-tftp = true;
      tftp-root = "${netbootTftpRoot}";
      "dhcp-boot" = [
        "tag:netboot,tag:httpboot,${netbootIpxeUrl},,${serviceIp}"
        "tag:netboot,tag:!httpboot,snponly.efi,,${serviceIp}"
      ];
      "dhcp-option-force" = [ "tag:httpboot,60,HTTPClient" ];
      # Generated from network.nix hosts that have a MAC address.
      "dhcp-host" = network.toDnsmasqDhcpHost;
      # Generated from network.nix hosts (and their extraNames). Each name
      # produces bare, lan-FQDN, and public-FQDN records.
      "address" = network.toDnsmasqAddress;
    };
  };

  services.fail2ban.enable = true;

  services.prometheus.exporters = {
    dnsmasq.enable = true;
  };

  services.nginx = {
    enable = true;
    virtualHosts."strix-netboot-router" = {
      serverAliases = [ routerIp serviceIp ];
      listen = [
        {
          addr = routerIp;
          port = 80;
        }
        {
          addr = serviceIp;
          port = 80;
        }
      ];
      locations."/strix-netboot/ipxe/" = {
        alias = "${netbootIpxe}/";
      };
      locations."/strix-netboot/by-mac/" = {
        alias = "${netbootByMac}/";
      };
      locations."/strix-netboot/hosts/" = {
        proxyPass = "http://${trexIp}/hosts/";
        extraConfig = ''
          proxy_set_header Host ${trexIp};
          proxy_buffering off;
        '';
      };
    };
  };

  networking.firewall.interfaces.${lanName} = {
    allowedTCPPorts = [ 80 ];
    allowedUDPPorts = [ 69 ];
  };

  services.tor = {
    enable = true;
    openFirewall = true;

    client = {
      enable = true;
      transparentProxy.enable = true;
      socksListenAddress = {
        IsolateDestAddr = true;
        # Keep the legacy listener through the gateway handoff.  Unlike DNS
        # and netboot, this service cannot be bound to both addresses through
        # the NixOS client option, and its consumers move in a later deploy.
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
