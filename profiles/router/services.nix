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
  secureHosts = lib.filterAttrs (_: h: h.strix.secureBoot or false) netbootHosts;
  secureState = "/var/lib/strix-secure-boot";
  secureCertificate = ../../secrets/strix-secure-boot-db.pem;
  secureOrigin = "http://${trexIp}:${toString network.netbootHttpPort}/hosts/secure";
  secureIpxeUrl = "${netbootBaseUrl}/secure/snponly-secure.efi";
  secureByMac = pkgs.linkFarm "strix-secure-router-selectors" (lib.concatLists (
    lib.mapAttrsToList (name: host: map (mac: {
      name = "${mac}.ipxe";
      path = pkgs.writeText "secure-router-${name}.ipxe" ''
        #!ipxe
        chain --name @0 ${netbootBaseUrl}/secure/${name}/current/boot.efi
      '';
    }) (netbootMacs host)) secureHosts
  ));
in {
  assertions = [ {
    assertion = builtins.attrNames netbootHosts == builtins.attrNames secureHosts;
    message = "All Strix netboot clients must enable firmware Secure Boot.";
  } ];

  environment.persistence.${config.sconfig.impermanence.persistentStoragePath}.directories =
    lib.optionals (secureHosts != {}) [ secureState ];
  systemd.tmpfiles.rules = lib.optionals (secureHosts != {}) [
    "d ${secureState} 0755 root root -"
    # Remove the old unsigned TFTP alias on existing installations.
    "r ${secureState}/snponly.efi - - - -"
  ];
  systemd.services.strix-secure-boot-sync-ipxe = lib.mkIf (secureHosts != {}) {
    description = "Cache verified Strix Secure Boot loaders and UKIs";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    unitConfig.RequiresMountsFor = [ secureState ];
    serviceConfig = {
      Type = "oneshot";
      Restart = "on-failure";
      RestartSec = 15;
    };
    script = ''
      set -euo pipefail
      mkdir -p ${secureState}
      stage=$(${pkgs.coreutils}/bin/mktemp -d ${secureState}/.sync.XXXXXX)
      trap 'rm -rf "$stage"' EXIT
      ${pkgs.curl}/bin/curl --fail --silent --show-error --max-time 60 \
        --output "$stage/ipxe.efi" ${secureOrigin}/ipxe/snponly.efi
      ${pkgs.sbsigntool}/bin/sbverify --cert ${secureCertificate} "$stage/ipxe.efi"
      ${lib.concatMapStringsSep "\n" (name: ''
        mkdir "$stage/${name}"
        ${pkgs.curl}/bin/curl --fail --silent --show-error --max-time 120 \
          --output "$stage/${name}/boot.efi" ${secureOrigin}/${name}/current/boot.efi
        ${pkgs.sbsigntool}/bin/sbverify --cert ${secureCertificate} "$stage/${name}/boot.efi"
        ${pkgs.binutils}/bin/objcopy --dump-section .cmdline="$stage/cmdline" \
          "$stage/${name}/boot.efi" "$stage/inspected.efi"
        # Host identity is checked inside the signed payload, not HTTP metadata.
        tr -d '\000' < "$stage/cmdline" | ${pkgs.gnugrep}/bin/grep -Eq \
          '^init=/nix/store/[a-z0-9]{32}-nixos-system-${name}-[^ /]+/init '
        hash=$(sha256sum "$stage/${name}/boot.efi" | cut -d' ' -f1)
        mkdir -p ${secureState}/${name}/generations
        generation=${secureState}/${name}/generations/$hash
        chmod 0755 "$stage/${name}"
        chmod 0644 "$stage/${name}/boot.efi"
        if [ -e "$generation" ]; then
          ${pkgs.diffutils}/bin/cmp "$stage/${name}/boot.efi" "$generation/boot.efi"
        else
          mv -T "$stage/${name}" "$generation"
        fi
        ln -s "generations/$hash" "$stage/current"
        mv -Tf "$stage/current" ${secureState}/${name}/current
      '') (builtins.attrNames secureHosts)}
      chmod 0644 "$stage/ipxe.efi"
      mv -T "$stage/ipxe.efi" ${secureState}/snponly-secure.efi
    '';
  };
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
      # signed iPXE over TFTP, which immediately switches back to HTTP.
      "dhcp-mac" = lib.concatLists (
        lib.mapAttrsToList
          (_: h: map (mac: "set:netboot,${mac}") (netbootMacs h))
          netbootHosts
      );
      "dhcp-vendorclass" = [ "set:httpboot,HTTPClient" ];
      enable-tftp = true;
      tftp-root = secureState;
      "dhcp-boot" = lib.optionals (secureHosts != {}) [
        "tag:netboot,tag:httpboot,${secureIpxeUrl},,${serviceIp}"
        "tag:netboot,tag:!httpboot,snponly-secure.efi,,${serviceIp}"
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
      locations."/strix-netboot/secure/" = lib.mkIf (secureHosts != {}) {
        alias = "${secureState}/";
      };
      locations."/strix-netboot/secure/by-mac/" = lib.mkIf (secureHosts != {}) {
        alias = "${secureByMac}/";
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
