{pkgs, ...}: let
  storage = import ../trex/spdk-storage-constants.nix;
  nqn = storage.modelsNqn;
  targetAddress = "192.168.25.208";
  hostAddress = "192.168.25.207";
  # Name the pinned snapshot's namespace UUID, so this host can only ever mount
  # the exact snapshot spdk-storage-constants.nix pins -- never "whatever is
  # currently exported". Not the XFS UUID (identical across all snapshots, so
  # it floats) and not nvme-SPDK_bdev_Controller_TREXMODELS01_N (that N is the
  # namespace ID and moves). The previous value here omitted the suffix
  # entirely and so resolved to nothing at all.
  device = "/dev/disk/by-id/nvme-uuid.${storage.modelsSnapshot.uuid}";
in {
  boot.kernelModules = ["nvme-rdma"];

  environment.systemPackages = [
    pkgs.fio
    pkgs.nvme-cli
  ];

  systemd.services.nvme-trex-models = {
    description = "Connect trex's read-only models snapshot over NVMe/RDMA";
    wantedBy = ["multi-user.target"];
    after = [
      "fuckup-rdma-vf.service"
      "network-online.target"
    ];
    wants = ["network-online.target"];
    requires = ["fuckup-rdma-vf.service"];
    path = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.iproute2
      pkgs.kmod
      pkgs.nvme-cli
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail

      # The service is safe to restart: do not create a second controller for
      # the same NQN when one is already live.
      if grep -Fxq ${nqn} /sys/class/nvme-subsystem/*/subsysnqn 2>/dev/null; then
        exit 0
      fi

      # Wait for the endpoint by ADDRESS, never by interface name. The VF's
      # name follows whichever PF holds the fabric cable, and pinning a name
      # here duplicated fabric-rdma-vf.nix's pfName/vfName -- when the cable
      # moved to NIC port 2 on 2026-08-06 this copy went stale and the service
      # reported "not configured" while the endpoint was in fact up.
      for _ in {1..100}; do
        if ip -4 -oneline address show |
          grep -Fq "inet ${hostAddress}/"; then
          break
        fi
        sleep 0.1
      done
      ip -4 -oneline address show |
        grep -Fq "inet ${hostAddress}/" || {
          echo "RoCE endpoint ${hostAddress} is not configured" >&2
          exit 1
        }

      modprobe nvme-rdma
      nvme connect \
        --transport=rdma \
        --traddr=${targetAddress} \
        --trsvcid=4420 \
        --nqn=${nqn} \
        --host-traddr=${hostAddress}
    '';
    preStop = ''
      nvme disconnect --nqn=${nqn} || true
    '';
  };

  # RemainAfterExit records a successful connect, not the continued existence
  # of its controller. Reconcile the NQN and pinned namespace so target loss
  # cannot leave a permanently stale active/exited client unit.
  systemd.services.nvme-trex-models-reconcile = {
    description = "Reconcile trex models NVMe/RDMA connection";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    path = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.systemd
    ];
    unitConfig.StartLimitIntervalSec = 0;
    serviceConfig.Type = "oneshot";
    script = ''
      set -euo pipefail

      nqn_controller_live() {
        for subsystem in /sys/class/nvme-subsystem/*; do
          [ -r "$subsystem/subsysnqn" ] || continue
          read -r subsystem_nqn <"$subsystem/subsysnqn"
          [ "$subsystem_nqn" = ${nqn} ] || continue
          for controller in "$subsystem"/nvme*; do
            [ -r "$controller/state" ] || continue
            read -r controller_state <"$controller/state"
            [ "$controller_state" = live ] && return 0
          done
        done
        return 1
      }

      state=$(systemctl show --property=ActiveState --value nvme-trex-models.service)
      [ "$state" = activating ] && exit 0

      mount_was_active=false
      systemctl is-active --quiet 'mnt-trex\x2dmodels.mount' \
        && mount_was_active=true

      if [ "$state" = active ] && [ -b ${device} ] && nqn_controller_live; then
        if [ "$mount_was_active" = false ] \
          && ! systemctl is-active --quiet 'mnt-trex\x2dmodels.automount'; then
          echo "models connection is live but its lazy automount is not; restarting it" >&2
          systemctl restart 'mnt-trex\x2dmodels.automount'
        fi
        exit 0
      fi

      echo "models connector, live controller, or pinned block device is absent; reconnecting" >&2
      systemctl restart nvme-trex-models.service
      if [ "$mount_was_active" = true ]; then
        systemctl restart 'mnt-trex\x2dmodels.mount'
      else
        systemctl start 'mnt-trex\x2dmodels.automount'
      fi
    '';
  };

  systemd.timers.nvme-trex-models-reconcile = {
    description = "Retry stale trex models NVMe/RDMA clients";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "30s";
      OnUnitInactiveSec = "1min";
      AccuracySec = "1s";
      Unit = "nvme-trex-models-reconcile.service";
    };
  };

  fileSystems."/mnt/trex-models" = {
    inherit device;
    fsType = "xfs";
    options = [
      "_netdev"
      "nofail"
      "ro"
      # A frozen XFS snapshot is consistent, but XFS still regards its log as
      # requiring recovery on a new host.  The SPDK lvol snapshot correctly
      # rejects those writes, so mount without replaying the frozen log.
      "norecovery"
      "x-systemd.automount"
      "x-systemd.device-timeout=30s"
      "x-systemd.requires=nvme-trex-models.service"
      "x-systemd.after=nvme-trex-models.service"
    ];
  };
}
