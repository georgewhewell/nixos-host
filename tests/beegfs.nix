{ pkgs, ... }:

# Three-node BeeGFS cluster: server1 runs mgmtd + meta + one storage target,
# server2 runs a second storage target, client mounts the filesystem via the
# kernel module. Verifies connection auth, striping across both targets and
# data integrity over remount. RDMA is off (QEMU has no verbs devices);
# everything runs over the BeeMsg TCP paths.
let
  connAuth = pkgs.writeText "conn.auth" "beegfs-vm-test-secret";

  common = { ... }: {
    imports = [ ../modules/beegfs.nix ];
    services.beegfs-cluster = {
      # Must be a literal IP: the client kernel module has no DNS resolver.
      # The test framework assigns 192.168.1.N in alphabetical node order.
      mgmtdHost = "192.168.1.2";
      connAuthFile = "${connAuth}";
      rdma = false;
    };
    virtualisation.memorySize = 1536;
    # Meta first-run init creates ~65k hash directories; the default 1G test
    # image has exactly 65536 ext4 inodes. Give the nodes headroom.
    virtualisation.diskSize = 4096;
  };
in
{
  name = "beegfs";

  nodes = {
    server1 = { ... }: {
      imports = [ common ];
      services.beegfs-cluster = {
        mgmtd = {
          enable = true;
          openFirewall = true;
        };
        meta = {
          enable = true;
          directory = "/var/lib/beegfs/meta";
          openFirewall = true;
        };
        storage = {
          enable = true;
          directories = [ "/var/lib/beegfs/storage1" ];
          openFirewall = true;
        };
      };
    };

    server2 = { ... }: {
      imports = [ common ];
      services.beegfs-cluster.storage = {
        enable = true;
        directories = [ "/var/lib/beegfs/storage2" ];
        openFirewall = true;
      };
    };

    client = { ... }: {
      imports = [ common ];
      services.beegfs-cluster.client = {
        enable = true;
        mounts."/mnt/beegfs" = { };
      };
    };
  };

  testScript = ''
    start_all()

    # Sync on full boot first: wait_for_unit fast-fails on "inactive with no
    # pending jobs", which races units still waiting on network-online.
    for machine in [server1, server2, client]:
        machine.wait_for_unit("multi-user.target")

    server1.wait_for_unit("beegfs-mgmtd.service")
    server1.wait_for_unit("beegfs-meta.service")
    server1.wait_for_unit("beegfs-storage.service")
    server2.wait_for_unit("beegfs-storage.service")

    # Nodes register with mgmtd on first start; give the handshakes a moment
    # and then require both storage targets to be present.
    server1.wait_until_succeeds(
        "beegfs node list --node-type storage --mgmtd-addr 127.0.0.1:8010 "
        "--tls-disable --auth-file ${connAuth} | grep -c storage | grep -qx 2",
        timeout=120,
    )

    client.wait_for_unit("multi-user.target")
    client.wait_until_succeeds(
        "systemctl restart mnt-beegfs.mount && mountpoint -q /mnt/beegfs",
        timeout=120,
    )

    # Write more than one chunk (default chunk size 512K) so the file
    # stripes across both targets.
    client.succeed(
        "dd if=/dev/urandom of=/mnt/beegfs/stripetest bs=1M count=16",
        "sha256sum /mnt/beegfs/stripetest > /mnt/beegfs/stripetest.sum",
    )

    # Both storage targets must hold chunk data for the striped file.
    server1.succeed(
        "find /var/lib/beegfs/storage1/chunks -type f -size +1M | grep -q ."
    )
    server2.succeed(
        "find /var/lib/beegfs/storage2/chunks -type f -size +1M | grep -q ."
    )

    # Data must survive a remount (nothing served from the page cache).
    client.succeed(
        "umount /mnt/beegfs",
        "systemctl restart mnt-beegfs.mount",
        "cd /mnt/beegfs && sha256sum -c stripetest.sum",
    )
  '';
}
