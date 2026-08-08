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
      path = [pkgs.iproute2];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -eu
        # Egress classification: packets marked DSCP ${toString cfg.dscp} leave on
        # priority ${toString cfg.priority}, which is the switch's lossless class.
        dcb app add dev ${cfg.interface} dscp-prio ${toString cfg.dscp}:${toString cfg.priority}
        # PFC on that priority only. Global 802.3x pause is deliberately NOT set
        # here: it pauses the whole link and causes head-of-line blocking, and
        # measurement showed it made raw RDMA worse, not better.
        dcb pfc set dev ${cfg.interface} prio-pfc ${toString cfg.priority}:on
      '';
      preStop = ''
        ${pkgs.iproute2}/bin/dcb pfc set dev ${cfg.interface} prio-pfc ${toString cfg.priority}:off || true
        ${pkgs.iproute2}/bin/dcb app del dev ${cfg.interface} dscp-prio ${toString cfg.dscp}:${toString cfg.priority} || true
      '';
    };
  };
}
