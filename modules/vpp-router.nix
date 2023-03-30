{ config, pkgs, lib, ... }:

let
  cfg = config.sconfig.vpp-router;
in

{
  options.sconfig.vpp-router = {
    enable = lib.mkEnableOption "VPP router";
    package = lib.mkOption
      {
        type = lib.types.package;
        default = pkgs.vpp;
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
        default = 77;
        description = ''
          inside subnet
        '';
      };
  };

  config = lib.mkIf cfg.enable {

    environment.etc."vpp-startup.conf".text = ''
      unix {
        nodaemon
        log /var/log/vpp/vpp.log
        full-coredump
        cli-listen /run/vpp/cli.sock
        startup-config /setup.gate
        poll-sleep-usec 100
        gid vpp
      }

      api-segment {
        gid vpp
      }

      dpdk {
          ${builtins.concatStringsSep "\n" (map (port: ''
          dev ${port}
          '') dpdks)}
       }

       plugins {
         ## Disable all plugins, selectively enable specific plugins
         ## YMMV, you may wish to enable other plugins (acl, etc.)
         plugin default { disable }
         plugin dhcp_plugin.so { enable }
         plugin dns_plugin.so { enable }
         plugin dpdk_plugin.so { enable }
         plugin nat_plugin.so { enable }
         plugin ping_plugin.so { enable }
       }
    '';

    environment.etc."vpp-run.gate".text =
      let
        hostname = "gateway";
        inherit (cfg) trunk downstream inside_subnet;
        trunk_mac = "50:6B:4B:03:04:CB";
        bvi_mac = "48:f8:b3:01:01:02";
        features = {
          adl = true;
          mactime = true;
          nat44 = true;
          cnat = true;
          ovpn = true;
          ike_responder = true;
          ipv6 = true;
          dns = true;
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
        set int ip address bvi0 192.168.${inside_subnet}.1/24
        set int state bvi0 up

        ${builtins.concatStringsSep "\n" (map (port: ''
        set int l2 bridge ${port} 1
        set int state ${port} up
        '') downstream)}

        comment { dhcp server and host-stack access }
        create tap host-if-name lstack host-ip4-addr 192.168.${inside_subnet}.2/24 host-ip4-gw 192.168.${inside_subnet}.1
        set int l2 bridge tap0 1
        set int state tap0 up

        service restart isc-dhcp-server

        ${lib.optionalString features.adl ''
        { bin adl_interface_enable_disable ${trunk} }
        { ip table 1 }
        { ip route add table 1 0.0.0.0/0 via local }
        ''}

        ${lib.optionalString features.nat44 ''
        { nat44 forwarding enable }
        { nat44 plugin enable sessions 63000 }
        { nat44 add interface address ${trunk} }
        { set interface nat44 in bvi0 out ${trunk} }
        { nat44 add static mapping local 192.168.${inside_subnet}.2 22342 external ${trunk} 22342 tcp }

        ${lib.optionalString features.ike_responder ''
        { nat44 add identity mapping external ${trunk} udp 500 }
        { nat44 add identity mapping external ${trunk} udp 4500 }
        ''}

        ${lib.optionalString features.dns ''
        { nat44 add static mapping local 192.168.${inside_subnet}.2 53053 external ${trunk} 53053 udp }
        ''}
        ${lib.optionalString features.ovpn ''
        { nat44 add static mapping local 192.168.${inside_subnet}.2 37979 external ${trunk} 37979 udp }
        { set interface feature bvi0 skipnat arc ip4-unicast }
        { ip route add 192.168.10.0/24 via 192.168.${inside_subnet}.2 }
        ''}
        ''}

        ${lib.optionalString features.cnat ''
        { set cnat snat-policy none }
        { set cnat snat-policy addr ${trunk} }
        { set interface feature bvi0 cnat-snat-ip4 arc ip4-unicast }
        { cnat translation add proto tcp real ${trunk} 22342 to -> 192.168.${inside_subnet}.2 22342 }
        ${lib.optionalString features.dns ''
        { cnat translation add proto udp real ${trunk} 53053 to -> 192.168.${inside_subnet}.1 53053 }
        ''}
        ${lib.optionalString features.ovpn ''
        { cnat translation add proto udp real ${trunk} 37979 to -> 192.168.${inside_subnet}.2 37979 }
        { set interface feature bvi0 skipnat arc ip4-unicast }
        { ip route add 192.168.10.0/24 via 192.168.${inside_subnet}.2 }
        ''}
        ''}

        ${lib.optionalString features.dns ''
        { nat44 add identity mapping external ${trunk} udp 53053 }
        { bin dns_name_server_add_del 8.8.8.8 }
        { bin dns_enable_disable }
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
        uncomment { ikev2 profile set swan traffic-selector local ip-range 192.168.${inside_subnet}.0 - 192.168.${inside_subnet}.255 port-range 0 - 65535 protocol 0 }
        uncomment { create ipip tunnel src 73.120.164.15 dst 162.255.170.167 }
        uncomment { ikev2 profile set swan tunnel ipip0 }
        uncomment { set int mtu packet 1390 ipip0 }
        uncomment { set int unnum ipip0 use ${trunk} }
        ''}

        ${lib.optionalString features.mactime ''
        comment { if using the mactime plugin, configure it }
        { bin mactime_add_del_range name roku mac 00:00:01:de:ad:be allow-static }

        ${builtins.concatStringsSep "\n" (map (port: ''
        { bin mactime_enable_disable ${port} }
        '') downstream)}
        ''}

        $(FEATURE_MODEM_ROUTE) { ip route add 192.168.100.1/32 via ${trunk} }
      '';

    systemd.services.vpp = {
      description = "run vpp";
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        ExecPreStart = "${pkgs.bash}/bin/bash -c 'mkdir -p /var/log/vpp/ /run/vpp'";
        ExecStart = "${cfg.package}/bin/vpp -c /etc/vpp-startup.conf";
      };
    };
  }
