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
  # and which one every client mounts. Upgrading is a reviewable diff and
  # rolling back is a revert.
  #
  # THE PROCEDURE for publishing a new model set (in this order):
  #   1. Get /mnt/optane/models to the state you want and run
  #      `spdk-models-snapshot` on trex; paste the name/uuid it prints here.
  #   2. Deploy trex (colmena apply switch --on trex). The export refuses to
  #      swap namespaces while any controller is connected -- SPDK 26.01
  #      SEGVs on a live swap (twice, 2026-07-31) -- so if clients are
  #      attached it drops the listener and logs "swap pending".
  #   3. Drain every controller: unmount /models and stop nvme-trex-models on
  #      strix-1/2/3/4, and unmount /mnt/trex-models plus stop the same unit on
  #      fuckup. All four Strix machines now netboot; trex's closure builds and
  #      serves their new images. Reboot all four after the namespace swaps,
  #      then restart/remount the local-disk fuckup client.
  #   4. Within a minute of the last controller dropping, the retry timer
  #      completes the swap and re-adds the listener; rebooted clients mount
  #      the new snapshot by its UUID. Verify with
  #      `nvmf_get_subsystems | jq ...namespaces[].uuid` against the pin.
  # Client fstabs name /dev/disk/by-id/nvme-uuid.<uuid>, so a client on a
  # stale generation simply gets no device (nofail, mount absent) rather
  # than the wrong data.
  #
  # `uuid` is the lvol snapshot's own UUID. SPDK propagates a bdev's UUID to
  # the NVMe namespace, the kernel exposes it, and udev creates
  # /dev/disk/by-id/nvme-uuid.<uuid> — so a client naming that path can only
  # ever get this exact snapshot.
  #
  # Deliberately NOT keys for the client mount:
  #   - the XFS UUID (2f53a91e-d215-4344-9702-eb8cda15ea8d) and LABEL
  #     "optmodels" are identical across every snapshot, because snapshots are
  #     block-level copies. Mounting by those makes the client float onto
  #     whatever happens to be exported.
  #   - /dev/disk/by-id/nvme-SPDK_bdev_Controller_TREXMODELS01_N: the trailing
  #     N is the namespace ID, which changes as namespaces are added/removed.
  #
  # The full migrated model set (bpool/trex/models is destroyed): Kimi-K3,
  # both GLM-5.2 quants, ds4, gguf/, flm/, llama-2-7b, the Qwen ggufs, plus a
  # partial Inkling (~715 GB of 1.9 TB, stopped by request, hf-resumable).
  # The HF hub .cache was deliberately NOT migrated -- entries re-fetch on
  # demand at ~1.7 GB/s rather than copying 1.5 TB of cold cache from HDDs.
  #
  # Sizing note: the models lvol grew 4.5 -> 7 TiB (2026-07-30, Inkling would
  # not fit). That abandons the "volume + one full worst-case snapshot + qb
  # <= store" rule from the ENOSPC post-mortem in favour of the realistic
  # model: snapshots of an append-mostly volume cost only their delta, and the
  # whole-device-write pathology that created a full-size snapshot is
  # understood and avoided. The free-space guard in spdk-models-snapshot
  # remains the hard backstop. Note ublk does NOT propagate a live lvol
  # resize: growing requires umount + ublk stop/start + xfs_growfs.
  modelsSnapshot = {
    name = "models-20260826-004351";
    uuid = "377c424f-3010-48dd-92fa-9c73092228db";
  };

  # calc-iobuf.py minimum for 8 reactor cores + RDMA + ublk is 8184.
  # The default 8192 leaves only eight buffers, while a new channel needs 128.
  iobufSmallPoolCount = 16384;

  # SPDK 26.05 also accounts the large-buffer caches strictly. The 1024
  # default cannot create the namespace channel at all. At 4096, the live
  # topology's cache capacities total 2848 entries (accel 272, bdev 272,
  # ublk 256, NVMf/RDMA 2048), leaving 1248 entries beyond those caches.
  # At 132 KiB each the full pool is ~528 MiB, inside the 6 GiB DPDK arena.
  iobufLargePoolCount = 4096;
}
