{
  config,
  lib,
  network,
  pkgs,
  ...
}:
let
  topology = network.routing.hostPf;
  transit = network.vlans.${topology.network};
  transitNetwork = "${transit.prefix}.0/${toString transit.cidr}";
  dpuTransitIp = network.ipOf topology.network topology.dpu.address;
  dpuTransit = "${dpuTransitIp}/${toString transit.cidr}";
  routerTransitIp = network.ipOf topology.network topology.router.address;
  routerTransit = "${routerTransitIp}/${toString transit.cidr}";
  dpuCfg = config.bluefield2.hostPf;
  routerCfg = config.bluefieldHostPf;
  representor = topology.dpu.representorName;
  vppInterface = topology.dpu.vppName;
  dataName = network.ports.bluefield2.vppData.vppName;
in
{
  options.bluefield2 = {
    hostPf.mode = lib.mkOption {
      type = lib.types.enum [
        "off"
        "linux-bridge"
        "vpp-representor"
      ];
      default = "off";
      description = "BlueField host-PF ownership mode.";
    };

    vpp.dataplaneDriver = lib.mkOption {
      type = lib.types.enum [
        "rdma"
        "dpdk"
      ];
      default = "rdma";
      description = ''
        Driver for the external BlueField VPP port. In vpp-representor mode,
        DPDK EAL discovers both the physical uplink and the host-PF
        representor; the sidecar names and configures the latter after VPP
        starts.
      '';
    };
  };

  options.bluefieldHostPf.routerMode = lib.mkOption {
    type = lib.types.enum [
      "off"
      "source-policy"
    ];
    default = "off";
    description = ''
      Optional router-side point-to-point host-PF transit. Source-policy
      mode is selected only by traffic explicitly bound to the /30 address;
      it cannot replace the copper LAN route or default route.
    '';
  };

  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = routerCfg.routerMode == "off" || topology.network != "lan";
          message = "The optional host-PF transit must not reuse the LAN service network.";
        }
        {
          assertion = routerCfg.routerMode == "off" || !config.networking.nat.enable;
          message = "The staged host-PF service router must not regain NAT/gateway ownership.";
        }
        {
          # The VPP RDMA plugin cannot use the physical port after the eswitch
          # transition. The mlx5 DPDK PMD supports the physical/uplink ethdev
          # in switchdev mode (through its bifurcated Verbs control path) and
          # is the only supported external dataplane for this experiment.
          assertion =
            dpuCfg.mode != "vpp-representor"
            || config.bluefield2.vpp.dataplaneDriver == "dpdk";
          message = "BlueField VPP host-PF/switchdev mode requires the DPDK dataplane; the VPP RDMA interface is not supported after the eswitch transition.";
        }
      ];
    }

    # The host NIC and RShim management function are in separate IOMMU groups
    # on router. Keep both drivers alive: either endpoint may disappear while
    # the copper .31 service path continues booting and serving the LAN.
    (lib.mkIf (routerCfg.routerMode == "source-policy") {
      systemd.services.bluefield-nic-bind.wantedBy = lib.mkOverride 40 [ "multi-user.target" ];
      systemd.services.bluefield-rshim.conflicts = lib.mkForce [ ];

      systemd.network.links."20-bluefield-hostpf" = {
        matchConfig = {
          Driver = "mlx5_core";
          PermanentMACAddress = topology.router.mac;
        };
        linkConfig = {
          Name = topology.router.linuxName;
          MTUBytes = toString transit.mtu;
        };
      };

      systemd.network.networks."80-bluefield-hostpf" = {
        matchConfig.Name = topology.router.linuxName;
        address = [ routerTransit ];
        routes = [
          {
            Destination = transitNetwork;
            Scope = "link";
            Table = topology.table;
            Metric = 10;
          }
        ]
        ++ map (destination: {
          Destination = destination;
          Gateway = dpuTransitIp;
          Table = topology.table;
          Metric = 10;
        }) topology.routes.routerToDpu
        ++ [
          {
            # A process bound to the test address may reach only the peer
            # and the explicit fabric prefixes. It cannot leak onto WAN.
            Destination = "0.0.0.0/0";
            Type = "unreachable";
            Table = topology.table;
            Metric = 32767;
          }
        ];
        routingPolicyRules = [
          {
            From = "${routerTransitIp}/32";
            Table = topology.table;
            Priority = topology.rulePriority;
            Family = "ipv4";
          }
        ];
        networkConfig = {
          DHCP = "no";
          IPv6AcceptRA = false;
          LinkLocalAddressing = "no";
        };
        linkConfig = {
          MTUBytes = toString transit.mtu;
          RequiredForOnline = "no";
        };
      };

      networking.firewall.interfaces.${topology.router.linuxName} = {
        # Test listeners only. DNS, DHCP, media, and the default route remain
        # bound to the ordinary service/copper interfaces.
        allowedTCPPorts = [ 5201 ];
        allowedUDPPorts = [ 5201 ];
      };
    })

    (lib.mkIf (dpuCfg.mode == "vpp-representor") {
      # switchdev can destroy and recreate the physical netdev. Serialize it
      # ahead of the existing link-mode/FEC unit, which in turn precedes VPP.
      systemd.services.bluefield-vpp-lab-link.after = [ "bluefield-switchdev.service" ];

      # Prefer the native DPDK host-PF representor requested by EAL
      # devargs. VPP names additional ethdevs sharing bf0's PCI address as
      # bf0/<DPDK-port-id>; discover and rename that interface at runtime so
      # neither its DPDK port number nor a PCI-derived name is hard-coded.
      # Retain AF_PACKET as a compatibility fallback for vendor kernels that
      # expose pf0hpf as a Linux representor instead.
      systemd.services.bluefield-hostpf-vpp = {
        description = "Attach the optional BlueField host-PF representor to VPP";
        wantedBy = [ "multi-user.target" ];
        wants = [
          "vpp.service"
          "bluefield-switchdev.service"
        ];
        after = [
          "vpp.service"
          "bluefield-switchdev.service"
        ];
        path = [
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.iproute2
          config.services.vpp.package
        ];
        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = "5s";
        };
        script = ''
          set -u
          while true; do
            if vppctl show version >/dev/null 2>&1; then
              if ! vppctl show interface 2>/dev/null \
                   | grep -q '^${vppInterface}[[:space:]]'; then
                dpdk_representor="$({
                  vppctl show interface 2>/dev/null \
                    | grep -E '^${dataName}/[0-9]+[[:space:]]' \
                    | head -n 1 \
                    | cut -d ' ' -f 1
                } || true)"
                if [ -n "$dpdk_representor" ]; then
                  vppctl set interface name "$dpdk_representor" '${vppInterface}' || true
                elif ip link show dev '${representor}' >/dev/null 2>&1; then
                  ip link set dev '${representor}' mtu '${toString transit.mtu}' promisc on up || true
                  if ! vppctl create host-interface name '${representor}' \
                       hw-addr '${topology.dpu.vppMac}'; then
                    sleep 5
                    continue
                  fi
                fi
              fi

              if vppctl show interface 2>/dev/null \
                   | grep -q '^${vppInterface}[[:space:]]'; then
                vppctl set interface mtu packet '${toString transit.mtu}' '${vppInterface}' || true
                vppctl set interface state '${vppInterface}' up || true
                if ! vppctl show interface address '${vppInterface}' 2>/dev/null \
                     | grep -Fq '${dpuTransitIp}/'; then
                  vppctl set interface ip address '${vppInterface}' '${dpuTransit}' || true
                fi
              fi
            fi
            sleep 5
          done
        '';
        preStop = ''
          vppctl delete host-interface name '${representor}' 2>/dev/null || true
          ip link set dev '${representor}' promisc off down 2>/dev/null || true
        '';
      };
    })
  ];
}
