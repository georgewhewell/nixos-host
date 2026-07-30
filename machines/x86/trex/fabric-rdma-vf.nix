{
  lib,
  network,
  ...
}: let
  rdma = network.hosts."trex-rdma";
  vfName = "mlxlan0v1";
  # Switchdev representor for the same VF: frames leaving mlxlan0v1 traverse
  # mlxlan0r1 on their way through ovs-mlx to the PF uplink.
  repName = "mlxlan0r1";
in {
  # RoCE endpoint for this host.
  #
  # The OVS internal port (ovs-host) carries trex's fabric address but is a
  # software port with no verbs device, so RDMA consumers cannot bind it —
  # SPDK's NVMe-oF target fails with "ibv_context is null". Instead we keep one
  # ConnectX-4 SR-IOV VF in the host namespace: mlxlan0v1 is a real mlx5
  # function (verbs device mlx5_1), and its switchdev representor mlxlan0r1 is
  # already a port on the ovs-mlx bridge, so frames reach the fabric through
  # the same PF uplink as everything else. Untagged, matching the CRS804
  # cage-4 access port's pvid 25.
  # This exact match must sort before default.nix's broad 10-mlx5-vf rule,
  # which deliberately marks every other mlxlan0v* interface unmanaged.
  systemd.network.networks."09-mlx-rdma-vf" = {
    matchConfig.Name = vfName;
    address = [(network.cidrOf "fabric" rdma.addresses.fabric)];
    # VF MACs are unset by the PF (all-zero), so without this the driver picks
    # a random one on every boot and the fabric relearns it each time.
    linkConfig = {
      MACAddress = rdma.mac;
      MTUBytes = "9000";
      ActivationPolicy = "up";
      RequiredForOnline = "no";
    };
    # Directly connected fabric only; the default route stays on ovs-host.
    # No router advertisements either: this is a storage-only endpoint, and
    # accepting RAs here autoconfigured both a global and a rogue ULA prefix
    # from the LAN (ovs-host carries a PrefixAllowList for the same reason).
    networkConfig = {
      LinkLocalAddressing = "ipv6";
      IPv6AcceptRA = false;
    };
  };

  # The representor must carry the same MTU as the VF, or jumbo frames are
  # silently dropped one hop into the host and RoCE is stuck at a 1024-byte
  # path MTU. With the VF at 9000 and this left at default.nix's implicit
  # 1500, every frame over 1500 bytes vanished between mlxlan0v1 and the wire:
  # ping -M do -s 1972 to a fabric peer failed while -s 1472 succeeded, and
  # NVMe-oF reads at 1 MiB collapsed to 3.7 MiB/s with I/O timeouts and
  # controller reconnects. Raising it took the same test to 2279 MiB/s.
  # Must sort before default.nix's broad 10-mlx5-rep rule, which matches
  # every mlxlan0r* and would otherwise win and leave this one at 1500.
  systemd.network.networks."09-mlx-rdma-rep" = {
    matchConfig.Name = repName;
    linkConfig = {
      MTUBytes = "9000";
      ActivationPolicy = "up";
      RequiredForOnline = "no";
    };
  };

  # ovs-host and this VF both hold addresses in the fabric subnet, so with the
  # default arp_ignore=0 either interface may answer ARP for either address.
  # A peer that learns .208 behind ovs-host's MAC would have its RoCE frames
  # delivered to the OVS port instead of the VF, where no verbs device can
  # process them. Reply only for addresses on the receiving interface, and
  # source ARP from the address that belongs to the outgoing one.
  boot.kernel.sysctl = {
    "net.ipv4.conf.all.arp_ignore" = lib.mkDefault 1;
    "net.ipv4.conf.all.arp_announce" = lib.mkDefault 2;
  };
}
