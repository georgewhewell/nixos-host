{ config, pkgs, lib, ... }:

let
  cfg = config.sconfig.vpp-router;
  MB = 1024 * 1024;
in

{
  options.sconfig.vpp-router = {
    enable = lib.mkEnableOption "VPP router";
    package = lib.mkOption
      {
        type = lib.types.package;
        default = config.services.vpp.package;
        description = ''
          vpp package
        '';
      };

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
          features = {
            adl = false;
            mactime = false;
            nat44 = true;
            cnat = false;
            ovpn = false;
            ike_responder = false;
            ipv6 = false;
            dns = false;
          };
        in
        ''
          show macro
          set int mac address ${trunk} ${trunk_mac}
          set dhcp client intfc ${trunk} hostname ${hostname}
          set int state ${trunk} up

          bvi create instance 0
          set int mac address bvi0 ${bvi_mac}
          set int l2 bridge bvi0 1 bvi
          set int ip address bvi0 192.168.${toString inside_subnet}.1/24
          set int state bvi0 up

          ${builtins.concatStringsSep "\n" (map (port: ''
          set int l2 bridge ${port} 1
          set int state ${port} up
          '') downstream)}

          comment { dhcp server and host-stack access }
          create tap host-if-name lstack host-ip4-addr 192.168.${toString inside_subnet}.254/24 host-ip4-gw 192.168.${toString inside_subnet}.1
          set int l2 bridge tap0 1
          set int state tap0 up

          ${lib.optionalString features.adl ''
          bin adl_interface_enable_disable ${trunk}
          ip table 1
          ip route add table 1 0.0.0.0/0 via local
          ''}

          ${lib.optionalString features.nat44 ''
          nat44 plugin enable sessions 63000
          nat44 forwarding enable
          nat44 add interface address ${trunk}
          set interface nat44 in bvi0 out ${trunk}
          nat44 add static mapping local 192.168.${toString inside_subnet}.254 22 external ${trunk} 22 tcp

          ${lib.optionalString features.ike_responder ''
          nat44 add identity mapping external ${trunk} udp 500
          nat44 add identity mapping external ${trunk} udp 4500
          ''}

          ${lib.optionalString features.dns ''
          nat44 add static mapping local 192.168.${toString inside_subnet}.254 53053 external ${trunk} 53053 udp
          ''}
          ${lib.optionalString features.ovpn ''
          nat44 add static mapping local 192.168.${toString inside_subnet}.254 37979 external ${trunk} 37979 udp
          set interface feature bvi0 skipnat arc ip4-unicast
          ip route add 192.168.10.0/24 via 192.168.${toString inside_subnet}.254
          ''}
          ''}

          ${lib.optionalString features.cnat ''
          { set cnat snat-policy none }
          { set cnat snat-policy addr ${trunk} }
          { set interface feature bvi0 cnat-snat-ip4 arc ip4-unicast }
          { cnat translation add proto tcp real ${trunk} 22342 to -> 192.168.${toString inside_subnet}.254 22342 }
          ${lib.optionalString features.dns ''
          { cnat translation add proto udp real ${trunk} 53053 to -> 192.168.${toString inside_subnet}.1 53053 }
          ''}
          ${lib.optionalString features.ovpn ''
          { cnat translation add proto udp real ${trunk} 37979 to -> 192.168.${toString inside_subnet}.254 37979 }
          { set interface feature bvi0 skipnat arc ip4-unicast }
          { ip route add 192.168.10.0/24 via 192.168.${toString inside_subnet}.2 }
          ''}
          ''}

          ${lib.optionalString features.dns ''
          nat44 add identity mapping external ${trunk} udp 53053
          bin dns_name_server_add_del 1.1.1.1
          bin dns_enable_disable
          ''}

          ${lib.optionalString features.ipv6 ''
          uncomment { set int ip6 table ${trunk} 0 }
          uncomment { ip6 nd address autoconfig ${trunk} default-route }
          uncomment { dhcp6 client ${trunk} }
          uncomment { dhcp6 pd client ${trunk} prefix group hgw }
          uncomment { set ip6 address bvi0 prefix group hgw ::1/64 }
          uncomment { ip6 nd address autoconfig bvi0 default-route }
          comment { iPhones seem to need lots of RA messages... }
          uncomment { ip6 nd bvi0 ra-managed-config-flag ra-other-config-flag ra-interval 30 20 ra-lifetime 180 }
          comment { ip6 nd bvi0 prefix 0::0/0  ra-lifetime 100000 }
          ''}

          ${lib.optionalString features.ike_responder ''
          comment { responder profile }
          uncomment { ikev2 profile add swan }
          uncomment { ikev2 profile set swan auth rsa-sig cert-file /home/dbarach/certs/swancert.pem }
          uncomment { set ikev2 local key /home/dbarach/certs/dorakey.pem }
          uncomment { ikev2 profile set swan id remote fqdn swan.barachs.net }
          uncomment { ikev2 profile set swan id local fqdn broiler2.barachs.net }
          uncomment { ikev2 profile set swan traffic-selector remote ip-range 192.168.1.0 - 192.168.1.255 port-range 0 - 65535 protocol 0 }
          uncomment { ikev2 profile set swan traffic-selector local ip-range 192.168.${toString inside_subnet}.0 - 192.168.${toString inside_subnet}.255 port-range 0 - 65535 protocol 0 }
          uncomment { create ipip tunnel src 73.120.164.15 dst 162.255.170.167 }
          uncomment { ikev2 profile set swan tunnel ipip0 }
          uncomment { set int mtu packet 1390 ipip0 }
          uncomment { set int unnum ipip0 use ${trunk} }
          ''}

          ${lib.optionalString features.mactime ''
          comment { if using the mactime plugin, configure it }
          { bin mactime_add_del_range name roku mac 00:00:01:de:ad:be allow-static }

          ${builtins.concatStringsSep "\n" (map (port: ''
          bin mactime_enable_disable ${port}
          '') downstream)}
          ''}

          # $(FEATURE_MODEM_ROUTE) { ip route add 192.168.100.1/32 via ${trunk} }
        '';
      # startup = pkgs.writeText "startup.conf" ''
      #   unix {
      #     nodaemon
      #     log /var/log/vpp/vpp.log
      #     full-coredump
      #     cli-listen /run/vpp/cli.sock
      #     startup-config ${setup}
      #     gid vpp
      #     poll-sleep-usec 100
      #   }

      #   cpu {
      #     skip-cores 2
      #     main-core 3
      #     workers 2
      #   }

      #   api-segment {
      #     gid vpp
      #   }

      #   logging {
      #     default-log-level debug
      #     default-syslog-log-level info
      #   }

      #   plugins {
      #     plugin default { disable }

      #     add-path ${cfg.package}/lib/vpp_plugins

      #     plugin linux_cp_plugin.so { enable }
      #     plugin linux_nl_plugin.so { enable }
      #     plugin acl_plugin.so { enable }
      #     plugin dhcp_plugin.so { enable }
      #     plugin dpdk_plugin.so { enable }
      #     plugin nat_plugin.so { enable }
      #     plugin ping_plugin.so { enable }
      #   }

      #   dpdk {
      #     dev default {
      #       devargs safe-mode-support=1
      #     }
      #     ${builtins.concatStringsSep "\n" (map (port: ''
      #     dev ${port}
      #     '') cfg.dpdks)}
      #   }

      #   linux-cp {
      #     lcp-sync
      #     lcp-auto-subint
      #   }
      # '';
    in
    lib.mkIf cfg.enable {

      # users.users.vpp = {
      #   group = "vpp";
      #   isSystemUser = true;
      # };
      # users.groups.vpp = { };

      environment.systemPackages = [ cfg.package pkgs.dpdk pkgs.pciutils ];

      boot.extraModulePackages = [
        config.boot.kernelPackages.dpdk-kmods
      ];

      # boot.kernel.sysctl =
      #   {
      #     # Set netlink buffer size.
      #     "net.core.rmem_default" = lib.mkDefault (cfg.netlinkBufferSize * MB);
      #     "net.core.wmem_default" = lib.mkDefault (cfg.netlinkBufferSize * MB);
      #     "net.core.rmem_max" = lib.mkDefault (cfg.netlinkBufferSize * MB);
      #     "net.core.wmem_max" = lib.mkDefault (cfg.netlinkBufferSize * MB);
      #   };

      networking = {
        useNetworkd = true;
        useDHCP = false;

        # No local firewall.
        nat.enable = false;
        firewall.enable = false;
      };

      systemd.network = {
        enable = true;
        wait-online.anyInterface = true;
        networks = {
          "10-lstack" = {
            matchConfig.Name = "lstack";
            linkConfig.RequiredForOnline = "enslaved";
            address = [
              # configure addresses including subnet mask
              "192.168.23.1/24"
            ];
            dhcpV4Config.RouteMetric = 1;
            networkConfig = {
              ConfigureWithoutCarrier = true;
              IPv6AcceptRA = true;
            };
          };
        };
      };
      networking.nameservers = [ "1.1.1.1" ];

      boot.kernelParams = [
        "default_hugepagesz=1G"
        "hugepagesz=1G"
        "hugepages=16"
        "isolcpus=2,3,4,5,6,7"
        "intel_iommu=on"
        "vfio-pci.ids=8086:188c,8086:1521,8086:1563"
      ];

      services.dnsmasq = {
        enable = true;
        # dhcp-option=6,1.1.1.1
        extraConfig = ''
          domain-needed
          bogus-priv
          no-hosts
          log-dhcp
          domain=lan
          bind-interfaces
          interface=lstack
          dhcp-range=lstack,192.168.${toString cfg.inside_subnet}.10,192.168.${toString cfg.inside_subnet}.253,6h
          dhcp-option=option:router,192.168.${toString cfg.inside_subnet}.1
          dhcp-host=e4:8d:8c:a8:de:40,192.168.${toString cfg.inside_subnet}.2   # switch
          dhcp-host=80:2a:a8:80:96:ef,192.168.${toString cfg.inside_subnet}.3   # ap
          dhcp-host=0c:c4:7a:89:fb:37,192.168.${toString cfg.inside_subnet}.4   # ipmi
          # dhcp-host=0c:c4:7a:87:b9:d8,192.168.${toString cfg.inside_subnet}.5 # nixhost
          dhcp-host=78:11:dc:ec:86:ea,192.168.${toString cfg.inside_subnet}.6   # vacuum
          dhcp-host=f0:99:b6:42:49:05,192.168.${toString cfg.inside_subnet}.48  # phone
        '';
      };

      # dont start dnsmasq until vpp is up (and lstack created)
      systemd.services.dnsmasq = {
        requires = [ "sys-subsystem-net-devices-lstack.device" ];
        serviceConfig = {
          Restart = "on-failure";
          RestartSec = 5;
        };
      };

      # systemd.services.bind-vpp-gbe = {
      #   description = "bind vpp gbe";
      #   wantedBy = [ "multi-user.target" ];
      #   path = [ pkgs.which pkgs.dpdk pkgs.iproute2 ];
      #   serviceConfig = {
      #     Type = "oneshot";
      #     ExecStart = "${pkgs.dpdk}/bin/dpdk-devbind.py --bind=vfio-pci 0000:01:00.\*";
      #     Restart = "on-failure";
      #     RestartSec = 1;
      #   };
      # };

      # systemd.services.bind-vpp-10gbe = {
      #   description = "bind vpp 10gbe";
      #   wantedBy = [ "multi-user.target" ];
      #   path = [ pkgs.which pkgs.dpdk pkgs.iproute2 ];
      #   serviceConfig = {
      #     Type = "oneshot";
      #     ExecStart = "${pkgs.dpdk}/bin/dpdk-devbind.py --bind=vfio-pci 0000:03:00.\*";
      #     Restart = "on-failure";
      #     RestartSec = 1;
      #   };
      # };

      # systemd.services.bind-vpp-25gbe = {
      #   description = "bind vpp 25gbe";
      #   wantedBy = [ "multi-user.target" ];
      #   path = [ pkgs.which pkgs.dpdk pkgs.iproute2 ];
      #   serviceConfig = {
      #     Type = "oneshot";
      #     ExecStart = "${pkgs.dpdk}/bin/dpdk-devbind.py --bind=vfio-pci 0000:85:00.\*";
      #     Restart = "on-failure";
      #     RestartSec = 1;
      #   };
      # };

      services.vpp = {
        enable = cfg.enable;
        inherit bootstrap;
        statsegSize = 1024;
        mainHeapSize = 14;
        extraConfig =
          let
            dpdks = [
              # 10G
              # "0000:01:00.0"
              # "0000:01:00.1"

              # # 1G
              # "0000:03:00.0"
              # "0000:03:00.1"
              # "0000:03:00.2"
              # "0000:03:00.3"

              # 25G
              "0000:85:00.0"
              "0000:85:00.2"
            ];
          in
          ''
            dpdk {
              dev default {
                devargs safe-mode-support=1
              }
              ${builtins.concatStringsSep "\n" (map (port: ''
              dev ${port}
              '') dpdks)}
            }
          '';
      };
    };
}
