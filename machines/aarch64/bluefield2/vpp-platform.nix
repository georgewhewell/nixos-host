{network, driver ? "rdma", hostPfMode ? "off"}: let
  dataPort = network.ports.bluefield2.vppData;
  hostPf = network.routing.hostPf;
in {
  # Physical identity is fleet inventory, not a lab/production constant.
  dataInterface = dataPort.linuxName;
  dataName = dataPort.vppName;
  dataMac = dataPort.mac;
  link = dataPort.link;

  # One shared dataplane policy feeds both the isolated lab and the inactive
  # production renderer.  A driver A/B therefore cannot accidentally change
  # worker count, queues, hugepages, or buffer geometry at the same time.
  dataplane = {
    # The host-PF production closure selects the tested DPDK profile; the
    # separately named transition rollback retains RDMA. Shaping remains in
    # the CRS812 ASIC; neither VPP driver implements TM.
    driver = driver;
    dpdkPlatform = "bluefield";
    dpdkIovaMode = "va";
    dpdkRxDescriptors = 4096;
    # NVIDIA reserves mlx5 representor 65535 for the host PF. Request it only
    # in a host-PF closure; the rollback profiles still discover only the
    # physical uplink. The guarded target remains available for future
    # attended driver or firmware experiments.
    dpdkDevargs =
      "rxq_pkt_pad_en=1"
      + (if hostPfMode == "vpp-representor"
         then ",representor=${hostPf.dpu.dpdkRepresentor}"
         else "");
    dpdkDrivers = [
      "*/mlx5"
      "mempool/bucket"
      "mempool/ring"
      "mempool/stack"
      "bus/auxiliary"
      # VPP's Linux DPDK plugin includes the vmbus API unconditionally even
      # when this machine has no Hyper-V devices.
      "bus/vmbus"
    ];
    pciAddress = dataPort.pciAddress;
    hostPf = hostPf // { inherit (hostPf.dpu) representorName dpdkRepresentor; };
    mainCore = 1;
    workerCores = [ 2 3 4 5 6 7 ];
    hugepages2MiB = 1024;
    mainHeapSize = "3G";
    buffers = {
      perNuma = 65536;
      # Standard ibverbs needs one SGE large enough for a jumbo frame.  The
      # retained DPDK profile also uses 10 KiB to keep vector RX and jumbo.
      dataSize = {
        rdma = 10240;
        dpdk = 10240;
      };
    };
  };
}
