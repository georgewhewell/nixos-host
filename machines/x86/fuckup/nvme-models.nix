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

      for _ in {1..100}; do
        if ip -4 address show dev enp8s0f0v0 |
          grep -Fq "inet ${hostAddress}/"; then
          break
        fi
        sleep 0.1
      done
      ip -4 address show dev enp8s0f0v0 |
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
