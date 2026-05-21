lib:
rec {
  domains = {
    lan = "lan.satanic.link";
    public = "satanic.link";
  };

  # Each VLAN owns its subnet prefix and DHCP scope. id=null means untagged.
  # `prefix` is the first three octets; helpers append the host octet.
  vlans = {
    lan = {
      id = null;
      prefix = "192.168.23";
      cidr = 24;
      gatewayHost = 1;
      dhcp = { start = 32; end = 249; lease = "6h"; };
      role = "trusted";
    };
    iot = {
      id = 20;
      prefix = "192.168.20";
      cidr = 24;
      gatewayHost = 1;
      dhcp = { start = 32; end = 249; lease = "6h"; };
      role = "iot";
    };
    guest = {
      id = 30;
      prefix = "192.168.30";
      cidr = 24;
      gatewayHost = 1;
      dhcp = { start = 32; end = 249; lease = "6h"; };
      role = "guest";
    };
    mgmt = {
      id = 40;
      prefix = "192.168.40";
      cidr = 24;
      gatewayHost = 1;
      dhcp = { start = 32; end = 249; lease = "6h"; };
      role = "mgmt";
    };
    # not 802.1Q but lives in the same model so consumers can iterate uniformly
    wireguard = {
      id = null;
      prefix = "192.168.24";
      cidr = 24;
      gatewayHost = 1;
      role = "vpn";
    };
  };

  # A host can sit on multiple VLANs (e.g. the router on every one as gateway).
  # `addresses` maps vlan name -> host octet within that vlan's prefix.
  # `mac` is optional. `extraNames` are additional DNS aliases that resolve to the
  # host's primary IP (the lan address if present, else the first vlan listed).
  hosts = {
    router = {
      addresses = { lan = 1; iot = 1; guest = 1; mgmt = 1; };
      extraNames = [ "frigate" ];
    };
    "mikrotik-10g"    = { mac = "e4:8d:8c:a8:de:40"; addresses = { lan = 2; }; };
    ap                = { mac = "80:2a:a8:80:96:ef"; addresses = { lan = 3; }; };
    "x10-ipmi"        = { mac = "0c:c4:7a:89:fb:37"; addresses = { lan = 4; }; };
    nixhost           = { mac = "0c:c4:7a:87:b9:d8"; addresses = { lan = 5; }; };
    vacuum            = { mac = "78:11:dc:ec:86:ea"; addresses = { lan = 6; }; };
    fuckup            = { mac = "b8:6f:35:ab:31:89"; addresses = { lan = 7; }; };
    trex = {
      mac = "50:6b:4b:03:04:cb";
      addresses = { lan = 8; };
      extraNames = [ "jellyfin" "grafana" "home" "radarr" "sonarr" "autobrr" ];
    };
    "mikrotik-100g"   = { mac = "48:a9:8a:93:42:4c"; addresses = { lan = 9; }; };
    trx90bmc          = { mac = "9c:6b:00:57:31:77"; addresses = { lan = 10; }; };
    "apc-ups"         = { mac = "28:29:86:8b:3f:cb"; addresses = { lan = 11; }; extraNames = [ "apc8b3fcb" ]; };
    printer           = { mac = "b4:22:00:cf:18:63"; addresses = { lan = 12; }; };
    cerberus          = { mac = "c8:f0:9e:de:3c:2f"; addresses = { lan = 13; }; };
    n100              = { mac = "9c:6b:00:39:f3:91"; addresses = { lan = 14; }; };
    "arr-servers"     = { mac = "9e:9c:05:57:e8:11"; addresses = { lan = 15; }; };
    "zigbee-stick"    = { mac = "1c:69:20:a1:d7:9f"; addresses = { lan = 16; }; };
    nanokvm           = { mac = "38:7a:cc:40:41:e3"; addresses = { lan = 17; }; };
    "rock-5b"         = { mac = "00:e0:4c:68:02:e7"; addresses = { lan = 18; }; };
    "10g-onti"        = { mac = "d0:aa:5f:01:45:a8"; addresses = { lan = 20; }; };
    "gh-runner-grw"   = {                            addresses = { lan = 50; }; };
    "10g-poe"         = { mac = "00:23:79:00:57:90"; addresses = { lan = 21; }; };
    "nanokvm-wifi"    = {                            addresses = { lan = 22; }; };
    "poe-switch-10g"  = {                            addresses = { lan = 23; }; };
    "strix-1"         = { mac = "66:e3:1e:f3:e5:79"; addresses = { lan = 136; }; };
    "strix-2"         = { mac = "5a:e8:00:d3:73:de"; addresses = { lan = 192; }; };
  };

  # Reserved for future iterations. Keep keys present so consumers can import without churn.
  services = {};
  ports = {};

  # ---- Helpers (derived views) ----

  # "lan" 7  ->  "192.168.23.7"
  ipOf = vlanName: octet: "${vlans.${vlanName}.prefix}.${toString octet}";

  # Gateway IP of a vlan: gatewayIp "lan"  ->  "192.168.23.1"
  gatewayIp = vlanName: ipOf vlanName vlans.${vlanName}.gatewayHost;

  # Convenient shortcut for the lan gateway (the universal "router").
  routerIp = gatewayIp "lan";

  # "lan" 14  ->  "192.168.23.14/24"
  cidrOf = vlanName: octet: "${ipOf vlanName octet}/${toString vlans.${vlanName}.cidr}";

  # "trex"  ->  "trex.lan.satanic.link"   (internal LAN FQDN)
  fqdn = name: "${name}.${domains.lan}";

  # "trex"  ->  "trex.satanic.link"   (public-facing FQDN)
  publicFqdn = name: "${name}.${domains.public}";

  # The host's "primary" IP, used for DNS aliases. lan if present, else first vlan key.
  primaryIp = h: let
    vlanNames = builtins.attrNames h.addresses;
    pick = if builtins.elem "lan" vlanNames then "lan" else builtins.head vlanNames;
  in ipOf pick h.addresses.${pick};

  # NixOS networking.hosts shape: { "192.168.23.1" = [ "router" "frigate" ]; ... }
  # Aggregates all of a host's VLAN IPs and folds extraNames onto the primary.
  toNixosHosts = let
    flat = lib.flatten (lib.mapAttrsToList
      (name: h: lib.mapAttrsToList
        (vlanName: octet: {
          ip = ipOf vlanName octet;
          names = [ name ] ++ lib.optionals (ipOf vlanName octet == primaryIp h) (h.extraNames or []);
        })
        h.addresses)
      hosts);
  in lib.foldl'
    (acc: e: acc // { ${e.ip} = (acc.${e.ip} or []) ++ e.names; })
    {}
    flat;

  # dnsmasq dhcp-host shape: ["mac,ip" ...] for every host that has a MAC.
  toDnsmasqDhcpHost = lib.mapAttrsToList
    (name: h: "${h.mac},${primaryIp h}")
    (lib.filterAttrs (_: h: (h.mac or null) != null) hosts);

  # dnsmasq address shape: ["/fqdn/ip" ...]. Each host (and each of its
  # extraNames) gets bare, lan-FQDN and public-FQDN records, all pointing at
  # the primary IP. Generates a superset of the prior hand-written list.
  toDnsmasqAddress = let
    namesFor = name: h: [ name ] ++ (h.extraNames or []);
    recordsFor = name: h: let
      ip = primaryIp h;
    in lib.flatten (map (n: [
      "/${n}/${ip}"
      "/${n}.${domains.lan}/${ip}"
      "/${n}.${domains.public}/${ip}"
    ]) (namesFor name h));
  in lib.flatten (lib.mapAttrsToList recordsFor hosts);
}
