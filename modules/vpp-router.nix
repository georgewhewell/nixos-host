{ config, pkgs, lib, inputs, ... }:

let
  cfg = config.sconfig.vpp-router;
  package = inputs.vifino.packages.${pkgs.system}.vpp;
  MB = 1024 * 1024;
in

{
  # imports = [ inputs.vifino.nixosModules.vpp ];

  options.sconfig.vpp-router = {
    enable = lib.mkEnableOption "VPP router";
    trunk = lib.mkOption
      {
        type = lib.types.string;
        description = ''
          trunk interface
        '';
      };

    downstream = lib.mkOption
      {
        type = lib.types.listOf lib.types.string;
        default = [ ];
        description = ''
          downstream interfaces
        '';
      };

    dpdks = lib.mkOption
      {
        type = lib.types.listOf lib.types.string;
        default = [ ];
        description = ''
          pci ids to bind
        '';
      };

    inside_subnet = lib.mkOption
      {
        type = lib.types.int;
        default = 23;
        description = ''
          inside subnet
        '';
      };

    forwardedPorts = lib.mkOption
      {
        example = ''
          forwardedPorts = {
            "192.168.23.5" = [ 443 18080 ];
          };
        '';
        type = lib.types.attrsOf (lib.types.listOf lib.types.int);
        default = { };
        description = ''
          port forwards
        '';
      };

    netlinkBufferSize = lib.mkOption {
      type = lib.types.int;
      default = 64;
      description = ''
        Set the sysctl options for netlink buffer sizes (in Megabyte).
        Default (64MiB) should suffice for 1M routes.
      '';
    };
  };

  config =
    let
      bootstrap =
        let
          hostname = "gateway";
          inherit (cfg) trunk downstream inside_subnet;
          trunk_mac = "3c:ec:ef:d1:0e:f3";
          bvi_mac = "48:f8:b4:01:01:02";
        in
        ''
          nat44 plugin enable sessions 63000

          set interface state ${trunk} up
          set dhcp client intfc ${trunk} hostname gateway
          nat44 add interface address ${trunk}

          # bridged
          #nat44 forwarding enable
          bvi create instance 0
          set int mac address bvi0 3c:ec:ef:d1:0e:f7
          set int state bvi0 up
          set int l2 bridge bvi0 1 bvi
          set int ip address bvi0 192.168.23.1/24
          set interface nat44 in bvi0
          set interface nat44 out ${trunk} output-feature

          ${builtins.concatStringsSep "\n" (map (port: ''
          set int l2 bridge ${port} 1
          set int state ${port} up
          set interface nat44 in ${port}
          '') downstream)}

          create tap host-if-name lstack host-ip4-addr 192.168.${toString inside_subnet}.252/24 host-ip4-gw 192.168.${toString inside_subnet}.1
          set int l2 bridge tap0 1
          set int state tap0 up
          set interface nat44 in tap0

          # ipv6
          set int ip6 table ${trunk} 0
          ip6 nd address autoconfig ${trunk} default-route
          dhcp6 client ${trunk}
          dhcp6 pd client ${trunk} prefix group hgw

          # port forwwarding
          ${builtins.concatStringsSep "\n" (lib.flatten (lib.mapAttrsToList (ip: ports: map (port: ''
          nat44 add static mapping local ${ip} ${toString port} external ${trunk} ${toString port} tcp
          nat44 add static mapping local ${ip} ${toString port} external ${trunk} ${toString port} udp
          '') ports) cfg.forwardedPorts))}
        '';
    in
    lib.mkIf cfg.enable {

      services.usbmuxd.enable = true;

      boot.initrd.kernelModules = [
        "nf_tables"
        "nft_compat"
        "i40e"
        "ice"
      ];

      boot.kernelModules = [
        "ipmi_devintf"
        "ipmi_si"
        "tcp_bbr"
        "vfio-pci"
      ];

      users.users.vpp = {
        group = "vpp";
        isSystemUser = true;
      };

      users.groups.vpp = { };

      environment.systemPackages = [
        package
        pkgs.pciutils
      ];

      boot.extraModulePackages = [
        config.boot.kernelPackages.dpdk-kmods
      ];

      networking = {
        useNetworkd = true;
        useDHCP = false;

        # No local firewall.
        nat.enable = false;
        firewall.enable = false;
      };

      systemd.network = let bridgeName = "br0.lan"; in {
        enable = true;
        wait-online.anyInterface = true;
        netdevs."01-${bridgeName}" = {
          netdevConfig = {
            Kind = "bridge";
            Name = bridgeName;
          };
        };
        networks = {
          # "50-backup" = {
          #   matchConfig.Name = "eno2";
          #   address = [
          #     "192.168.23.253/24"
          #   ];
          #   routes = [
          #     { routeConfig.Gateway = "192.168.23.1"; }
          #   ];
          #   dhcpV4Config.RouteMetric = 99;
          #   networkConfig = {
          #     ConfigureWithoutCarrier = true;
          #     IPv6AcceptRA = true;
          #   };
          # };
          "20-lstack" = {
            matchConfig.Name = "lstack";
            # address = [
            #   "192.168.23.253/24"
            # ];
            # dhcpV4Config.RouteMetric = 1;
            networkConfig = {
              Bridge = bridgeName;
              ConfigureWithoutCarrier = true;
              IPv6AcceptRA = true;
            };
            linkConfig.RequiredForOnline = "enslaved";
          };
          # "10-vf" = {
          #   matchConfig.Name = "enp133s0f0np0";
          #   address = [
          #     "192.168.23.254/24"
          #   ];
          #   # routes = [
          #   #   { routeConfig.Gateway = "192.168.23.1"; }
          #   # ];
          #   dhcpV4Config.RouteMetric = 2;
          #   networkConfig = {
          #     ConfigureWithoutCarrier = true;
          #     IPv6AcceptRA = true;
          #   };
          # };
          "01-br0" = {
            matchConfig.Name = bridgeName;
            bridgeConfig = { };
            address = [
              "192.168.23.254/24"
            ];
            # routes = [
            #   {
            #     routeConfig.Destination = "192.168.23.0/24";
            #     routeConfig.Metric = 88;
            #     routeConfig.Gateway = "192.168.23.1";
            #   }
            # ];
            networkConfig = {
              ConfigureWithoutCarrier = true;
              IPv6AcceptRA = true;
            };
            routes = [
              { routeConfig.Gateway = "192.168.23.1"; }
            ];
          };
          "10-lan" = {
            matchConfig.Name = "enp2s0";
            networkConfig = {
              Bridge = bridgeName;
              ConfigureWithoutCarrier = true;
              IPv6AcceptRA = true;
            };
            linkConfig.RequiredForOnline = "enslaved";
          };
          # "10-vf" = {
          #   matchConfig.Name = "enp133s0f0np0";
          #   address = [
          #     "192.168.23.254/24"
          #   ];
          #   # routes = [
          #   #   { routeConfig.Gateway = "192.168.23.1"; }
          #   # ];
          #   dhcpV4Config.RouteMetric = 2;
          #   networkConfig = {
          #     ConfigureWithoutCarrier = true;
          #     IPv6AcceptRA = true;
          #   };
          # };
        };
      };

      networking.nameservers = [ "192.168.23.5" ];

      boot.kernelParams = [
        "intel_iommu=on"
        "iommu=pt"
      ];

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

      # set num hugepages..


      services.vpp = {
        enable = cfg.enable;
        package = package;
        uioDriver = "vfio-pci";
        inherit bootstrap;
        # statsegSize = 32;
        # mainHeapSize = 512;
        numberNumaNodes = 1;
        buffersPerNuma = 8;

        # workers = 2;
        pollSleepUsec = 1;
        additionalHugePages = 512; #  ??
        extraConfig = ''
          dpdk {
            ${builtins.concatStringsSep "\n" (map (port: ''
            dev ${port}
            '') cfg.dpdks)}
          }
        '';
      };
    };
}
