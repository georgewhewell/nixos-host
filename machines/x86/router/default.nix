{ config, pkgs, lib, ... }:

{
  /*
    router: xeon-d embedded
  */
  sconfig = {
    profile = "server";
    home-manager = {
      enable = true;
    };
    # vpp-router = {
    #   enable = true;
    #   dpdks = [
    #     # 10G
    #     # "0000:01:00.0"
    #     # "0000:01:00.1"

    #     # # 1G
    #     # "0000:03:00.0"
    #     # "0000:03:00.1"
    #     # "0000:03:00.2"
    #     # "0000:03:00.3"

    #     # 25G
    #     "0000:85:00.0"
    #     "0000:85:00.2"
    #   ];
    #   trunk = "TwentyFiveGigabitEthernet133/0/2";
    #   downstream = [
    #     "TwentyFiveGigabitEthernet133/0/0"
    #     # "TenGigabitEthernet1/0/0"
    #     # "TenGigabitEthernet1/0/1"
    #     # "GigabitEthernet3/0/0"
    #     # "GigabitEthernet3/0/1"
    #     # "GigabitEthernet3/0/2"
    #     # "GigabitEthernet3/0/3"
    #   ];
    #   inside_subnet = 25;
    # };
  };

  deployment.targetHost = "192.168.23.1";

  imports =
    [
      ../../../profiles/common.nix
      ../../../profiles/home.nix
      ../../../profiles/headless.nix
      ../../../profiles/uefi-boot.nix

      ../../../profiles/router.nix
      ../../../profiles/fastlan.nix
    ];

  services.iperf3 = {
    enable = true;
    openFirewall = true;
  };

  # services.udpxy = {
  #   enable = true;
  # };
  #
  # services.vpp =
  #   {
  #     enable = false;
  #     bootstrap =
  #       let
  #         hostname = "gateway";
  #         trunk = "TwentyFiveGigabitEthernet85/0/2";
  #         downstream = [
  #           "TwentyFiveGigabitEthernet85/0/0"
  #           "TenGigabitEthernet1/0/0"
  #           "TenGigabitEthernet1/0/1"
  #           "GigabitEthernet3/0/0"
  #           "GigabitEthernet3/0/1"
  #           "GigabitEthernet3/0/2"
  #           "GigabitEthernet3/0/3"
  #         ];
  #         inside_subnet = 25;
  #         trunk_mac = "3c:ec:df:d1:0e:cc";
  #         bvi_mac = "48:f8:b4:01:01:02";
  #         features = {
  #           adl = false;
  #           mactime = false;
  #           nat44 = true;
  #           cnat = false;
  #           ovpn = false;
  #           ike_responder = false;
  #           ipv6 = false;
  #           dns = false;
  #         };
  #       in
  #       ''
  #         show macro
  #         set int mac address ${trunk} ${trunk_mac}
  #         set dhcp client intfc ${trunk} hostname ${hostname}
  #         set int state ${trunk} up

  #         bvi create instance 0
  #         set int mac address bvi0 ${bvi_mac}
  #         set int l2 bridge bvi0 1 bvi
  #         set int ip address bvi0 192.168.${toString inside_subnet}.1/24
  #         set int state bvi0 up

  #         ${builtins.concatStringsSep "\n" (map (port: ''
  #         set int l2 bridge ${port} 1
  #         set int state ${port} up
  #         '') downstream)}

  #         comment { dhcp server and host-stack access }
  #         create tap host-if-name lstack host-ip4-addr 192.168.${toString inside_subnet}.254/24 host-ip4-gw 192.168.${toString inside_subnet}.1
  #         set int l2 bridge tap0 1
  #         set int state tap0 up

  #         ${lib.optionalString features.adl ''
  #         bin adl_interface_enable_disable ${trunk}
  #         ip table 1
  #         ip route add table 1 0.0.0.0/0 via local
  #         ''}

  #         ${lib.optionalString features.nat44 ''
  #         nat44 plugin enable sessions 63000
  #         nat44 forwarding enable
  #         nat44 add interface address ${trunk}
  #         set interface nat44 in bvi0 out ${trunk}
  #         nat44 add static mapping local 192.168.${toString inside_subnet}.254 22 external ${trunk} 22 tcp

  #         ${lib.optionalString features.ike_responder ''
  #         nat44 add identity mapping external ${trunk} udp 500
  #         nat44 add identity mapping external ${trunk} udp 4500
  #         ''}

  #         ${lib.optionalString features.dns ''
  #         nat44 add static mapping local 192.168.${toString inside_subnet}.254 53053 external ${trunk} 53053 udp
  #         ''}
  #         ${lib.optionalString features.ovpn ''
  #         nat44 add static mapping local 192.168.${toString inside_subnet}.254 37979 external ${trunk} 37979 udp
  #         set interface feature bvi0 skipnat arc ip4-unicast
  #         ip route add 192.168.10.0/24 via 192.168.${toString inside_subnet}.254
  #         ''}
  #         ''}

  #         ${lib.optionalString features.cnat ''
  #         { set cnat snat-policy none }
  #         { set cnat snat-policy addr ${trunk} }
  #         { set interface feature bvi0 cnat-snat-ip4 arc ip4-unicast }
  #         { cnat translation add proto tcp real ${trunk} 22342 to -> 192.168.${toString inside_subnet}.254 22342 }
  #         ${lib.optionalString features.dns ''
  #         { cnat translation add proto udp real ${trunk} 53053 to -> 192.168.${toString inside_subnet}.1 53053 }
  #         ''}
  #         ${lib.optionalString features.ovpn ''
  #         { cnat translation add proto udp real ${trunk} 37979 to -> 192.168.${toString inside_subnet}.254 37979 }
  #         { set interface feature bvi0 skipnat arc ip4-unicast }
  #         { ip route add 192.168.10.0/24 via 192.168.${toString inside_subnet}.2 }
  #         ''}
  #         ''}

  #         ${lib.optionalString features.dns ''
  #         nat44 add identity mapping external ${trunk} udp 53053
  #         bin dns_name_server_add_del 1.1.1.1
  #         bin dns_enable_disable
  #         ''}

  #         ${lib.optionalString features.ipv6 ''
  #         uncomment { set int ip6 table ${trunk} 0 }
  #         uncomment { ip6 nd address autoconfig ${trunk} default-route }
  #         uncomment { dhcp6 client ${trunk} }
  #         uncomment { dhcp6 pd client ${trunk} prefix group hgw }
  #         uncomment { set ip6 address bvi0 prefix group hgw ::1/64 }
  #         uncomment { ip6 nd address autoconfig bvi0 default-route }
  #         comment { iPhones seem to need lots of RA messages... }
  #         uncomment { ip6 nd bvi0 ra-managed-config-flag ra-other-config-flag ra-interval 30 20 ra-lifetime 180 }
  #         comment { ip6 nd bvi0 prefix 0::0/0  ra-lifetime 100000 }
  #         ''}

  #         ${lib.optionalString features.ike_responder ''
  #         comment { responder profile }
  #         uncomment { ikev2 profile add swan }
  #         uncomment { ikev2 profile set swan auth rsa-sig cert-file /home/dbarach/certs/swancert.pem }
  #         uncomment { set ikev2 local key /home/dbarach/certs/dorakey.pem }
  #         uncomment { ikev2 profile set swan id remote fqdn swan.barachs.net }
  #         uncomment { ikev2 profile set swan id local fqdn broiler2.barachs.net }
  #         uncomment { ikev2 profile set swan traffic-selector remote ip-range 192.168.1.0 - 192.168.1.255 port-range 0 - 65535 protocol 0 }
  #         uncomment { ikev2 profile set swan traffic-selector local ip-range 192.168.${toString inside_subnet}.0 - 192.168.${toString inside_subnet}.255 port-range 0 - 65535 protocol 0 }
  #         uncomment { create ipip tunnel src 73.120.164.15 dst 162.255.170.167 }
  #         uncomment { ikev2 profile set swan tunnel ipip0 }
  #         uncomment { set int mtu packet 1390 ipip0 }
  #         uncomment { set int unnum ipip0 use ${trunk} }
  #         ''}

  #         ${lib.optionalString features.mactime ''
  #         comment { if using the mactime plugin, configure it }
  #         { bin mactime_add_del_range name roku mac 00:00:01:de:ad:be allow-static }

  #         ${builtins.concatStringsSep "\n" (map (port: ''
  #         bin mactime_enable_disable ${port}
  #         '') downstream)}
  #         ''}

  #         # $(FEATURE_MODEM_ROUTE) { ip route add 192.168.100.1/32 via ${trunk} }
  #       '';
  #     extraConfig =
  #       let
  #         dpdks = [
  #           # 10G
  #           "0000:01:00.0"
  #           "0000:01:00.1"

  #           # 1G
  #           "0000:03:00.0"
  #           "0000:03:00.1"
  #           "0000:03:00.2"
  #           "0000:03:00.3"

  #           # 25G
  #           "0000:85:00.0"
  #           "0000:85:00.2"
  #         ];
  #       in
  #       ''
  #         dpdk {
  #           dev default {
  #             devargs safe-mode-support=1
  #           }
  #           ${builtins.concatStringsSep "\n" (map (port: ''
  #           dev ${port}
  #           '') dpdks)}
  #         }
  #       '';
  #   };

  boot.kernelPackages = pkgs.linuxPackages_latest_lto_icelake;
  # boot.kernelPackages = pkgs.linuxPackages_latest;
  nixpkgs.config.permittedInsecurePackages = [
    "nix-2.15.3"
  ];
  boot.kernelParams = [ "intel_pstate=active" ];

  fileSystems."/" =
    {
      device = "/dev/disk/by-uuid/0896549a-c162-4458-a0bb-3f397f91f538";
      fsType = "ext4";
    };

  fileSystems."/boot" =
    {
      device = "/dev/disk/by-uuid/2A3E-BFEC";
      fsType = "vfat";
    };

  boot.kernelModules = [
    "ipmi_devintf"
    "ipmi_si"
    "vfio_pci"
    "ixgbe"
    "i40e"
    "igb"
    "ice"
  ];

  services.thermald.enable = true;

  networking = {
    hostName = "router";
    hostId = lib.mkForce "deadbeef";
    enableIPv6 = true;
  };
}
