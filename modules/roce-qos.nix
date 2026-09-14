# Host-side RoCE QoS: mark RoCE as DSCP 26 -> priority 3 and turn on PFC there.
#
# The CRS804 already carries a complete lossless design (see
# machines/routeros/crs812/config.rsc): qos profile nixos-roce maps DSCP 26 to
# traffic-class 3, queue 3 has ECN enabled, lossless-traffic-class=3, and the
# nixos-pfc-tc3 profile enables PFC rx+tx on TC3 for every fabric port.
#
# The host half of that was never configured. Measured on 2026-08-09 before
# this module existed:
#
#   rx_prio3_bytes 0 / tx_prio3_bytes 0     -- priority 3 carried NO traffic
#   dcb pfc show: prio-pfc 3:off            -- PFC off on every priority
#   rx_global_pause 265                     -- falling back to 802.3x pause
#
# So every RoCE packet went out on priority 0, into the default queue: not
# lossless, no ECN, and not the queue the switch tunes. TCP shares that default
# queue and was fine, which is why TCP measured 28.2 Gb/s while RoCE did not.
#
# Honesty about what this fixed: enabling it moved traffic onto priority 3
# (tx_prio3_bytes climbs) but did NOT change throughput, because there was no
# packet loss for losslessness to prevent (packet_seq_err was already 0 after
# the switchdev removal). It is still correct -- the fabric is only lossless if
# both ends agree on the priority, and without it the switch's ECN/PFC policy
# is inert -- but it is not a performance fix on its own.
#
# There is no MLNX_OFED here, so /sys/class/infiniband/*/tc/1/traffic_class and
# cma_roce_tos do not exist. The DSCP an application emits therefore has to
# come from the application: nvme connect --tos / ib_*_bw -T. This module only
# sets up the mapping and the flow control; it cannot mark traffic by itself.
#
# Why this is a unit and not systemd-networkd: networkd has NO DCB support at
# all -- no PFC, no dscp-prio app table (systemd 261; the only DSCP key in the
# networkd module is CopyDSCP, a FooOverUDP tunnel option). So the `dcb` calls
# have to be imperative regardless.
#
# The `ethtool -A` flow-control call deliberately stays here too, even though
# .link files DO support RxFlowControl/TxFlowControl. A .link file is applied
# by udev when the device appears, and nothing re-applies it when an mlxlink
# adapter reset clobbers it later -- the same reset that wipes PFC. Keeping
# both settings in the single unit that afterUnits guarantees runs LAST is
# what makes them stick. Splitting them would look tidier and be less correct.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.sconfig.roceQos;
  # `interface` remains the established primary and retains the `roce-qos`
  # unit name. Extras are deliberately de-duplicated and cannot replace it.
  extraInterfaces = lib.filter (interface: interface != cfg.interface)
    (lib.unique cfg.extraInterfaces);
  mkAdditionalService = interface: {
    description = "RoCE DSCP->priority mapping and PFC on ${interface}";
    wantedBy = ["multi-user.target"];
    after = ["sys-subsystem-net-devices-${interface}.device"] ++ cfg.afterUnits;
    bindsTo = ["sys-subsystem-net-devices-${interface}.device"];
    # DCB state is per-netdev and is lost if the driver recreates it -- or if
    # anything in afterUnits resets the adapter under us.
    partOf = ["sys-subsystem-net-devices-${interface}.device"] ++ cfg.afterUnits;
    path = [pkgs.iproute2 pkgs.ethtool];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -eu
      dcb app add dev ${interface} dscp-prio ${toString cfg.dscp}:${toString cfg.priority}
      ${
        if cfg.globalPause
        then ''
          dcb pfc set dev ${interface} prio-pfc ${toString cfg.priority}:off || true
          ethtool -A ${interface} rx on tx on || true
        ''
        else ''
          ethtool -A ${interface} rx off tx off || true
          dcb pfc set dev ${interface} prio-pfc ${toString cfg.priority}:on
        ''
      }
    '';
    preStop = ''
      ${pkgs.iproute2}/bin/dcb pfc set dev ${interface} prio-pfc ${toString cfg.priority}:off || true
      ${pkgs.iproute2}/bin/dcb app del dev ${interface} dscp-prio ${toString cfg.dscp}:${toString cfg.priority} || true
    '';
  };
in {
  options.sconfig.roceQos = {
    enable = lib.mkEnableOption "RoCE DSCP-to-priority mapping and PFC on the fabric NIC";

    interface = lib.mkOption {
      type = lib.types.str;
      example = "mlxlan0";
      description = "Fabric netdev carrying RoCE traffic.";
    };

    extraInterfaces = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["cx5fabric1"];
      description = ''
        Additional fabric netdevs that receive the same DSCP-to-priority and
        PFC policy. Existing users of `interface` retain their `roce-qos`
        service; every extra interface receives its own service.
      '';
    };

    dscp = lib.mkOption {
      type = lib.types.int;
      default = 26;
      description = ''
        DSCP for RoCE. Must match the `nixos-roce` qos profile on the CRS804.
        Applications must emit this themselves -- ToS = dscp * 4 (+2 for ECT),
        so DSCP 26 is `--tos 106`.
      '';
    };

    globalPause = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to leave 802.3x global pause enabled on this NIC as well.

        Normally false: pause stops the entire link rather than one priority,
        causing head-of-line blocking, and it is redundant once PFC covers the
        RoCE priority. Measured worse for raw RDMA here, 5.90 vs 7.69 Gb/s.

        True only where the peer switch cannot do PFC. trex hangs off the
        CRS510, which has none (machines/routeros/crs510/config.rsc says so
        outright), and that switch actively pauses trex's port -- tx-pause was
        2543 on qsfp28-2-1. Turning pause off on that leg would make trex
        ignore those frames and the switch would drop instead.
      '';
    };

    priority = lib.mkOption {
      type = lib.types.int;
      default = 3;
      description = "802.1p priority / traffic class. Must match lossless-traffic-class on the switch.";
    };

    afterUnits = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["cx5-fabric-link.service"];
      description = ''
        Units that reset the adapter and therefore destroy its DCB state --
        anything running `mlxlink --link_mode_force`, for instance. This
        service is ordered after them AND made `partOf` them, so the DSCP
        mapping and PFC are always (re-)applied last.

        Without this the two race. Measured on strix-1, 2026-08-15: roce-qos
        finished at 18:07:19 and cx5-fabric2-link finished at 18:07:20, the
        mlxlink reset wiped PFC, and the node read at 448 MB/s instead of
        3525 MB/s. The unit reports success either way -- it genuinely did
        its work, something else undid it -- so the loser of the race is
        invisible in `systemctl status` and the slowness looks random per
        boot rather than per host.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services = {
      roce-qos = {
        description = "RoCE DSCP->priority mapping and PFC on ${cfg.interface}";
        wantedBy = ["multi-user.target"];
        after = ["sys-subsystem-net-devices-${cfg.interface}.device"] ++ cfg.afterUnits;
        bindsTo = ["sys-subsystem-net-devices-${cfg.interface}.device"];
        # Re-applied whenever the link reappears: dcb state is per-netdev and is
        # lost if the driver reloads, the interface is recreated, or anything in
        # afterUnits resets the adapter.
        partOf = ["sys-subsystem-net-devices-${cfg.interface}.device"] ++ cfg.afterUnits;
        path = [pkgs.iproute2 pkgs.ethtool];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          set -eu
          # Egress classification: packets marked DSCP ${toString cfg.dscp} leave on
          # priority ${toString cfg.priority}, which is the switch's lossless class.
          dcb app add dev ${cfg.interface} dscp-prio ${toString cfg.dscp}:${toString cfg.priority}
          # PFC and 802.3x global pause are MUTUALLY EXCLUSIVE on mlx5: enabling
          # pause silently clears the PFC configuration. Discovered the hard way
          # on 2026-08-09 -- the unit reported success while `dcb pfc show` came
          # back 3:off, because the ethtool call at the end undid the dcb call
          # before it. So this is strictly one or the other.
          ${
            if cfg.globalPause
            then ''
              # This NIC's peer switch cannot do PFC, so global pause is the only
              # backpressure available and PFC would be meaningless anyway -- the
              # switch would never send a priority pause frame.
              dcb pfc set dev ${cfg.interface} prio-pfc ${toString cfg.priority}:off || true
              ethtool -A ${cfg.interface} rx on tx on || true
            ''
            else ''
              # Peer switch speaks PFC: use it, and drop global pause so it
              # cannot clear the PFC state or block the whole link.
              ethtool -A ${cfg.interface} rx off tx off || true
              dcb pfc set dev ${cfg.interface} prio-pfc ${toString cfg.priority}:on
            ''
          }
        '';
        preStop = ''
          ${pkgs.iproute2}/bin/dcb pfc set dev ${cfg.interface} prio-pfc ${toString cfg.priority}:off || true
          ${pkgs.iproute2}/bin/dcb app del dev ${cfg.interface} dscp-prio ${toString cfg.dscp}:${toString cfg.priority} || true
        '';
      };
    } // lib.listToAttrs (map (interface:
      lib.nameValuePair "roce-qos-${interface}" (mkAdditionalService interface)
    ) extraInterfaces);
  };
}
