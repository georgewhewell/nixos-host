{
  lib,
  network,
  pkgs,
  ...
}: let
  transition = network.routing.production.transition;
  lanBridge = network.ports.router.lanBridge;
  wifiInterface = "${lanBridge}.${toString network.vlans.wifi.id}";
  wanInterface = network.ports.router.wan.linuxName;
  serviceIp = transition.controlPlane.targetIp;
  serviceIpv6 = transition.controlPlane.targetIpv6;
  wifiServiceIp = network.ipOf "wifi" transition.controlPlane.targetHost;
  wifiServiceIpv6 = "fdde:ad:${toString network.vlans.wifi.id}::${toString transition.controlPlane.targetHost}";
in {
  # Service-only base for the retired Linux router. The ordinary `router` node
  # adds the optional source-policy BlueField PF; `router-rollback` is the
  # separately named closure that can reclaim legacy gateway ownership.
  deployment.targetHost = lib.mkForce serviceIp;

  # The CX4, RTL8127, and external Thunderbolt NIC are no longer installed.
  # Keep that hardware in the explicit `router-rollback` closure, not in this
  # service-machine closure.
  router.legacyPcieNetwork.enable = false;

  assertions = [
    {
      assertion = serviceIp != transition.controlPlane.currentGatewayIp;
      message = "The service-only router must not retain VPP's LAN gateway address.";
    }
    {
      assertion = transition.mode == "legacy-flat";
      message = "The first router retirement closure only supports the legacy-flat handoff.";
    }
  ];

  # The service host no longer routes for the LAN, but it still terminates the
  # home WireGuard tunnel.  Forwarding must therefore remain enabled for the
  # two VPN interfaces; the early nftables guard below rejects every other
  # transit path so .31 cannot accidentally become a second LAN gateway.
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = lib.mkForce true;
    "net.ipv6.conf.all.forwarding" = lib.mkForce true;
  };

  networking.nftables.tables.router-service-forward-guard = {
    family = "inet";
    content = ''
      # Profiles generated before the gateway handoff still name .1 as DNS.
      # Redirect only home-VPN DNS to the service host; conntrack rewrites the
      # reply source back to .1, so existing iOS/macOS profiles need no edit.
      chain vpn_dns_compat {
        type nat hook prerouting priority dstnat; policy accept;

        iifname "wg-home" ip daddr ${transition.controlPlane.currentGatewayIp} udp dport 53 counter dnat ip to ${serviceIp}:53
        iifname "wg-home" ip daddr ${transition.controlPlane.currentGatewayIp} tcp dport 53 counter dnat ip to ${serviceIp}:53
      }

      chain forward {
        type filter hook forward priority -10; policy accept;

        iifname "wg-home" accept comment "home VPN may initiate LAN or full-tunnel traffic"
        oifname "wg-home" ct state established,related accept comment "return traffic to home VPN"

        # The later hydra-builders-guard table applies its narrower source,
        # destination and port policy to traffic entering this tunnel.
        iifname "wg-hydra-bld" accept comment "defer Hydra policy to its dedicated guard"
        oifname "wg-hydra-bld" ct state established,related accept comment "return traffic to Hydra tunnel"

        drop comment "service-only router must not forward other traffic"
      }
    '';
  };

  networking.nat.enable = lib.mkForce false;
  services.miniupnpd.enable = lib.mkForce false;
  sconfig.gcp-ddns.enable = lib.mkForce false;
  systemd.network.wait-online.enable = lib.mkForce false;

  # The BlueField host PF is not part of this service-only router's network;
  # keep the PCIe RShim recovery channel available instead.  rshim is a
  # Type=simple background service with no network-online dependency, so a
  # missing or unhealthy DPU cannot hold up boot.  Retry indefinitely without
  # bouncing back to the mutually-exclusive mlx5 host-PF binding between
  # attempts.
  systemd.services.bluefield-nic-bind.wantedBy = lib.mkForce [];
  systemd.services.bluefield-rshim = {
    wantedBy = ["multi-user.target"];
    after = ["systemd-modules-load.service"];
    unitConfig.StartLimitIntervalSec = 0;
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = "15s";
      ExecStopPost = lib.mkForce "${pkgs.coreutils}/bin/true";
    };
  };

  systemd.network.networks = {
    "10-${lanBridge}" = {
      address = lib.mkForce [
        "${serviceIp}/${toString network.vlans.lan.cidr}"
        "${serviceIpv6}/64"
        # Control-plane rescue subnet. It has to be repeated here rather than
        # only in profiles/router/linux.nix, because this mkForce replaces that
        # list wholesale -- which is exactly how the address silently failed to
        # appear on the first deploy of it.
        (network.cidrOf "rescue" network.hosts.router.addresses.rescue)
      ];
      routes = lib.mkForce [
        {
          Gateway = transition.controlPlane.currentGatewayIp;
          Metric = 10;
        }
      ];
      networkConfig = {
        DHCPPrefixDelegation = lib.mkForce false;
        IPv6SendRA = lib.mkForce false;
        IPv6Forwarding = lib.mkForce false;
      };
    };

    "30-${wifiInterface}" = {
      # dnsmasq must retain an address on the tagged Wi-Fi link to answer
      # broadcasts, but .50.1 and its RA move to VPP.
      address = lib.mkForce [
        "${wifiServiceIp}/${toString network.vlans.wifi.cidr}"
        "${wifiServiceIpv6}/64"
      ];
      networkConfig = {
        DHCPPrefixDelegation = lib.mkForce false;
        IPv6SendRA = lib.mkForce false;
        IPv6Forwarding = lib.mkForce false;
      };
    };

    "20-${wanInterface}" = {
      enable = false;
      networkConfig = {
        DHCP = lib.mkForce "no";
        IPv6AcceptRA = lib.mkForce false;
        IPv6Forwarding = lib.mkForce false;
      };
      linkConfig.RequiredForOnline = lib.mkForce "no";
    };
  };

  services.nginx.virtualHosts."strix-netboot-router".listen = lib.mkForce [
    {
      addr = serviceIp;
      port = 80;
    }
  ];

  services.esphome-dashboard.address = lib.mkForce serviceIp;

  # Application services must follow the old router to its service address;
  # the legacy gateway address is owned by VPP after this closure is applied.
  services.home-assistant.config.http.server_host = lib.mkForce serviceIp;

  services.tor = {
    client.socksListenAddress.addr = lib.mkForce serviceIp;
    settings.ControlPort = lib.mkForce [
      {addr = "127.0.0.1"; port = 9051;}
      {addr = serviceIp; port = 9051;}
    ];
  };
}
