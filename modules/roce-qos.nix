# Host-side RoCE QoS: mark RoCE as DSCP 26 -> priority 3 and turn on PFC there.
#
# The CRS804 already carries a complete lossless design (see
# machines/routeros/crs804/config.rsc): qos profile nixos-roce maps DSCP 26 to
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
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.sconfig.roceQos;
in {
  options.sconfig.roceQos = {
    enable = lib.mkEnableOption "RoCE DSCP-to-priority mapping and PFC on the fabric NIC";

    interface = lib.mkOption {
      type = lib.types.str;
      example = "mlxlan0";
      description = "Fabric netdev carrying RoCE traffic.";
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
  };

  config = lib.mkIf cfg.enable {
    systemd.services.roce-qos = {
      description = "RoCE DSCP->priority mapping and PFC on ${cfg.interface}";
      wantedBy = ["multi-user.target"];
      after = ["sys-subsystem-net-devices-${cfg.interface}.device"];
      bindsTo = ["sys-subsystem-net-devices-${cfg.interface}.device"];
      # Re-applied whenever the link reappears: dcb state is per-netdev and is
      # lost if the driver reloads or the interface is recreated.
      partOf = ["sys-subsystem-net-devices-${cfg.interface}.device"];
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
  };
}
