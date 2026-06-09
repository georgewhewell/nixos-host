lib: rec {
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
      mtu = 9000;
      gatewayHost = 1;
      dhcp = {
        start = 32;
        end = 249;
        lease = "6h";
      };
      role = "trusted";
    };
    iot = {
      id = 20;
      prefix = "192.168.20";
      cidr = 24;
      gatewayHost = 1;
      dhcp = {
        start = 32;
        end = 249;
        lease = "6h";
      };
      role = "iot";
    };
    guest = {
      id = 30;
      prefix = "192.168.30";
      cidr = 24;
      gatewayHost = 1;
      dhcp = {
        start = 32;
        end = 249;
        lease = "6h";
      };
      role = "guest";
    };
    mgmt = {
      id = 40;
      prefix = "192.168.40";
      cidr = 24;
      gatewayHost = 1;
      dhcp = {
        start = 32;
        end = 249;
        lease = "6h";
      };
      role = "mgmt";
    };
    wifi = {
      id = 50;
      prefix = "192.168.50";
      cidr = 24;
      gatewayHost = 1;
      dhcp = {
        start = 32;
        end = 249;
        lease = "6h";
      };
      role = "trusted";
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

  benchmarkBuildHosts =
    let
      strixHaloRunner = {
        gpus = [
          {
            type = "amd";
            arch = "1151";
          }
        ];
        npus = [
          {
            type = "amd";
            arch = "xdna2";
          }
        ];
      };
      strixHaloSystemFeatures = [
        "gccarch-znver5"
        "rocm"
        "benchmark"
        "kvm"
        "nixos-test"
      ];
    in
    {
      strix-1 =
        strixHaloRunner
        // {
          ipv4 = "192.168.23.136";
          publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPHXYxvg1N//t89I4vktqPKg4yGgI5amT97GHt3mHStV";
          maxJobs = 1;
          speedFactor = 32;
          systems = [ "x86_64-linux" ];
          systemFeatures = strixHaloSystemFeatures;
        };
      strix-2 =
        strixHaloRunner
        // {
          ipv4 = "192.168.23.192";
          publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID0RsY9sp58nDjojVM9uAZ+6DoLxi/8LrGuonSoSC2DS";
          maxJobs = 1;
          speedFactor = 32;
          systems = [ "x86_64-linux" ];
          systemFeatures = strixHaloSystemFeatures;
        };
      mbp = {
        ipv4 = "192.168.23.24";
        publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEn8GwjuFsx8r3wXq0J28mHg2WZdbo4NH45bxg9EwSTO";
        maxJobs = 1;
        speedFactor = 64;
        systems = [ "aarch64-darwin" ];
        systemFeatures = [ "apple-virt" "benchmark" "big-parallel" "apple-m4" "metal" ];
        gpus = [ ];
      };
      goblin = {
        ipv4 = "192.168.23.247";
        publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDRJYI4x/nKcftcIo6pmy9gRR0NznkFUQ3eliggcGY9N";
        maxJobs = 1;
        speedFactor = 96;
        systems = [ "aarch64-darwin" ];
        systemFeatures = [ "apple-virt" "benchmark" "big-parallel" "apple-m4" "metal" ];
        gpus = [ ];
      };
    };

  hydraBuilders = {
    interface = "wg-hydra-bld";
    subnet = "10.101.0.0/24";
    ax102 = {
      wg = "10.101.0.2";
      endpoint = "213.239.212.173:51822";
      publicKey = "Y+jK3Cf2xVYvaYRy41MfKqINJarEdhBIlqWgFbCfF1U=";
    };
    router = {
      wg = "10.101.0.1";
    };
    builders = {
      trex = {
        ipv4 = "192.168.23.8";
      };
      fuckup = {
        ipv4 = primaryIp hosts.fuckup;
      };
      strix-1 = {
        ipv4 = benchmarkBuildHosts.strix-1.ipv4;
      };
      strix-2 = {
        ipv4 = benchmarkBuildHosts.strix-2.ipv4;
      };
      mbp = {
        ipv4 = benchmarkBuildHosts.mbp.ipv4;
      };
      goblin = {
        ipv4 = benchmarkBuildHosts.goblin.ipv4;
      };
    };
  };

  # A host can sit on multiple VLANs (e.g. the router on every one as gateway).
  # `addresses` maps vlan name -> host octet within that vlan's prefix.
  # `mac` is optional. `extraNames` are additional DNS aliases that resolve to the
  # host's primary IP (the lan address if present, else the first vlan listed).
  hosts = {
    router = {
      addresses = {
        lan = 1;
        iot = 1;
        guest = 1;
        mgmt = 1;
        wifi = 1;
      };
      extraNames = [ "frigate" ];
    };
    "mikrotik-10g" = {
      mac = "e4:8d:8c:a8:de:40";
      addresses = { lan = 2; };
    };
    ap = {
      mac = "80:2a:a8:80:96:ef";
      addresses = { lan = 3; };
    };
    "x10-ipmi" = {
      mac = "0c:c4:7a:89:fb:37";
      addresses = { lan = 4; };
    };
    nixhost = {
      mac = "0c:c4:7a:87:b9:d8";
      addresses = { lan = 5; };
    };
    vacuum = {
      mac = "78:11:dc:ec:86:ea";
      addresses = { lan = 6; };
    };
    fuckup = {
      mac = "b8:6f:35:ab:31:89";
      addresses = { lan = 7; };
    };
    trex = {
      mac = "50:6b:4b:03:04:cb";
      # mlxlan0 (100G Mellanox PF) historically grabbed a dynamic lease as a
      # standalone DHCP client before OVS enslaved it, registering trex -> a pool
      # address and shadowing the static .8 in DNS. Reserve its MAC to .8 too so
      # any stray lease resolves to the correct host instead of a dynamic IP.
      extraMacs = [ "50:6b:4b:0d:24:86" ];
      addresses = { lan = 8; };
      extraNames = [ "jellyfin" "grafana" "home" "radarr" "sonarr" "autobrr" ];
    };
    "mikrotik-100g" = {
      mac = "48:a9:8a:93:42:4c";
      addresses = { lan = 9; };
    };
    trx90bmc = {
      mac = "9c:6b:00:57:31:77";
      addresses = { lan = 10; };
    };
    "apc-ups" = {
      mac = "28:29:86:8b:3f:cb";
      addresses = { lan = 11; };
      extraNames = [ "apc8b3fcb" ];
    };
    printer = {
      mac = "b4:22:00:cf:18:63";
      addresses = { lan = 12; };
    };
    cerberus = {
      mac = "c8:f0:9e:de:3c:2f";
      addresses = { lan = 13; };
    };
    n100 = {
      mac = "9c:6b:00:39:f3:91";
      addresses = { lan = 14; };
    };
    "arr-servers" = {
      mac = "9e:9c:05:57:e8:11";
      addresses = { lan = 15; };
    };
    "zigbee-stick" = {
      mac = "1c:69:20:a1:d7:9f";
      addresses = { lan = 16; };
    };
    nanokvm = {
      mac = "38:7a:cc:40:41:e3";
      addresses = { lan = 17; };
    };
    "rock-5b" = {
      mac = "00:e0:4c:68:02:e7";
      addresses = { lan = 18; };
    };
    mbp = {
      mac = "c2:c5:7f:8c:7a:51";
      # mbp's LAN link is now the 2.5GbE Thunderbolt/USB ethernet (en11); reserve
      # .24 to its MAC too so `mbp` resolves to a stable address it actually holds
      # (bare `mbp` was a dead static record while it pulled a dynamic pool lease).
      extraMacs = [ "88:c9:b3:b3:2a:da" ];
      addresses = { lan = 24; };
    };
    goblin = {
      mac = "1c:1d:d3:eb:67:55";
      addresses = { lan = 247; };
    };
    "10g-onti" = {
      mac = "d0:aa:5f:01:45:a8";
      addresses = { lan = 20; };
    };
    "gh-runner-grw" = { addresses = { lan = 50; }; };
    "10g-poe" = {
      mac = "00:23:79:00:57:90";
      addresses = { lan = 21; };
    };
    "nanokvm-wifi" = { addresses = { lan = 22; }; };
    "poe-switch-10g" = { addresses = { lan = 23; }; };
    "strix-1" = {
      mac = "66:e3:1e:f3:e5:79";
      addresses = { lan = 136; };
    };
    "strix-2" = {
      mac = "5a:e8:00:d3:73:de";
      addresses = { lan = 192; };
    };
  };

  # Physical/logical network attachment points that are shared by multiple
  # host profiles or by out-of-band device configuration.
  ports = {
    router = {
      lanBridge = "br0.lan";
      wan = {
        linuxName = "enp1s0f0np0";
        mac = "50:6b:4b:03:04:ca";
      };
      lan25g = {
        linuxName = "enp1s0f1np1";
        mac = "50:6b:4b:03:04:cb";
      };
    };
  };

  # Reserved for future iterations. Keep keys present so consumers can import without churn.
  services = { };

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
  primaryIp = h:
    let
      vlanNames = builtins.attrNames h.addresses;
      pick =
        if builtins.elem "lan" vlanNames
        then "lan"
        else builtins.head vlanNames;
    in
    ipOf pick h.addresses.${pick};

  # NixOS networking.hosts shape: { "192.168.23.1" = [ "router" "frigate" ]; ... }
  # Aggregates all of a host's VLAN IPs and folds extraNames onto the primary.
  toNixosHosts =
    let
      flat = lib.flatten (lib.mapAttrsToList
        (name: h:
          lib.mapAttrsToList
            (vlanName: octet: {
              ip = ipOf vlanName octet;
              names = [ name ] ++ lib.optionals (ipOf vlanName octet == primaryIp h) (h.extraNames or [ ]);
            })
            h.addresses)
        hosts);
    in
    lib.foldl'
      (acc: e: acc // { ${e.ip} = (acc.${e.ip} or [ ]) ++ e.names; })
      { }
      flat;

  # dnsmasq dhcp-host shape: ["mac[,mac...],ip" ...] for every host that has a
  # MAC. A host may list extraMacs (other NICs on the same box); dnsmasq accepts
  # multiple hardware addresses sharing one reserved IP on a single dhcp-host
  # line, so each NIC resolves to the host's primary IP rather than a pool lease.
  toDnsmasqDhcpHost =
    lib.mapAttrsToList
      (name: h: "${lib.concatStringsSep "," ([ h.mac ] ++ (h.extraMacs or [ ]))},${primaryIp h}")
      (lib.filterAttrs (_: h: (h.mac or null) != null) hosts);

  # dnsmasq address shape: ["/fqdn/ip" ...]. Each host (and each of its
  # extraNames) gets bare, lan-FQDN and public-FQDN records, all pointing at
  # the primary IP. Generates a superset of the prior hand-written list.
  toDnsmasqAddress =
    let
      namesFor = name: h: [ name ] ++ (h.extraNames or [ ]);
      recordsFor = name: h:
        let
          ip = primaryIp h;
        in
        lib.flatten (map
          (n: [
            "/${n}/${ip}"
            "/${n}.${domains.lan}/${ip}"
            "/${n}.${domains.public}/${ip}"
          ])
          (namesFor name h));
    in
    lib.flatten (lib.mapAttrsToList recordsFor hosts);
}
