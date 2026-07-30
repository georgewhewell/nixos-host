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

  # calc-iobuf.py minimum for 8 reactor cores + RDMA + ublk is 8184.
  # The default 8192 leaves only eight buffers, while a new channel needs 128.
  iobufSmallPoolCount = 16384;
}
