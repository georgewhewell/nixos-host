{
  rpcSocket = "/run/spdk/spdk.sock";

  lvstore = "optstore";
  modelsLvol = "optstore/models";
  incompleteLvol = "optstore/qb-incomplete";

  modelsMount = "/mnt/optane/models";
  incompleteMount = "/var/lib/qbittorrent/incomplete";

  modelsNqn = "nqn.2026-07.link.satanic.trex:models";
  modelsSerial = "TREXMODELS01";
  modelsSnapshotPattern = "^optstore/models-[0-9]{8}-[0-9]{6}$";

  # THE PIN. This is the single place that decides which snapshot trex exports
  # and which one every client mounts. To publish a new model set: run
  # `spdk-models-snapshot` on trex, paste the name/uuid it prints here, and
  # deploy. Upgrading is then a reviewable diff and rolling back is a revert.
  #
  # `uuid` is the lvol snapshot's own UUID. SPDK propagates a bdev's UUID to
  # the NVMe namespace, the kernel exposes it, and udev creates
  # /dev/disk/by-id/nvme-uuid.<uuid> — so a client naming that path can only
  # ever get this exact snapshot.
  #
  # Deliberately NOT keys for the client mount:
  #   - the XFS UUID (7748df47-65fa-4182-bf98-666efc5661b1) and LABEL
  #     "optmodels" are identical across every snapshot, because snapshots are
  #     block-level copies. Mounting by those makes the client float onto
  #     whatever happens to be exported.
  #   - /dev/disk/by-id/nvme-SPDK_bdev_Controller_TREXMODELS01_N: the trailing
  #     N is the namespace ID, which changes as namespaces are added/removed.
  modelsSnapshot = {
    name = "models-20260730-092516";
    uuid = "4d22485e-5caa-4aae-a76e-a2f14263546d";
  };

  # calc-iobuf.py minimum for 8 reactor cores + RDMA + ublk is 8184.
  # The default 8192 leaves only eight buffers, while a new channel needs 128.
  iobufSmallPoolCount = 16384;
}
