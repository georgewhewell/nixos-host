{
  dpdk,
  lib,
  liburing,
  meson,
  ninja,
  procps,
  python3,
  rdma-core,
  spdk,
}: let
  # mlx5 SR-IOV VFs may report node_guid=0 even though the kernel CM has a
  # valid device index.  Unpatched librdmacm then leaves rdma_cm_id.verbs NULL,
  # which SPDK correctly rejects when creating an RDMA listener.
  rdma-core-for-spdk = rdma-core.overrideAttrs (old: {
    patches =
      (old.patches or [ ])
      ++ [ ./rdma-core-zero-node-guid.patch ];
  });
in

# nixpkgs' SPDK 26.01 package currently links against a newer external DPDK
# than SPDK accepts at runtime.  Use the DPDK revision vendored and tested by
# the SPDK release, and enable the ublk target needed to put kernel XFS above
# an SPDK bdev.
spdk.overrideAttrs (old: {
  pname = "spdk-ublk";

  patches =
    (old.patches or [ ])
    ++ [
      # Initramfs compatibility (systemd ROOT_STORAGE_DAEMONS deployment):
      # honor SPDK_CPU_LOCK_DIR/TMPDIR for core locks, and set argv[0][0]='@'
      # when /etc/initrd-release exists.
      ./initrd-compat.patch
    ];

  # Fail loudly if the patch above was silently skipped.
  postPatch =
    (old.postPatch or "")
    + ''
      grep -q cpu_lock_dir lib/event/app.c
      grep -q initrd-release lib/event/app.c
    '';

  buildInputs =
    builtins.filter (input: input != dpdk) (old.buildInputs or [ ])
    ++ [
      liburing
      rdma-core-for-spdk
    ];

  nativeBuildInputs =
    (old.nativeBuildInputs or [ ])
    ++ [
      meson
      ninja
      procps
      python3.pkgs.pyelftools
    ];

  # Meson/Ninja are tools for the vendored DPDK sub-build.  SPDK itself uses
  # its configure script and Makefiles.
  dontUseMesonConfigure = true;
  dontUseMesonBuild = true;
  dontUseMesonInstall = true;
  dontUseMesonCheck = true;
  dontUseNinjaBuild = true;
  dontUseNinjaInstall = true;
  dontUseNinjaCheck = true;

  configureFlags =
    builtins.filter
      (flag: !(lib.hasPrefix "--with-dpdk=" flag))
      (old.configureFlags or [ ])
    ++ [
      "--with-ublk"
      "--with-rdma"
    ];
})
