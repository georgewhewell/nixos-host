{
  dpdk,
  fetchFromGitHub,
  help2man,
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

# SPDK 26.05 and nixpkgs both use a DPDK 26.03 base, but SPDK's vendored fork
# carries its release-tested fixes. Use that fork, and enable the ublk target
# needed to put kernel XFS above an SPDK bdev.
spdk.overrideAttrs (old: {
  pname = "spdk-ublk";
  version = "26.05";

  src = fetchFromGitHub {
    owner = "spdk";
    repo = "spdk";
    tag = "v26.05";
    hash = "sha256-cTferOD+UW/t6ClrgmKdHKpfYc3iWwE31WedD3LsWoY=";
    fetchSubmodules = true;
  };

  patches =
    (old.patches or [ ])
    ++ [
      # Initramfs compatibility (systemd ROOT_STORAGE_DAEMONS deployment):
      # honor SPDK_CPU_LOCK_DIR/TMPDIR for core locks, and set argv[0][0]='@'
      # when /etc/initrd-release exists.
      ./initrd-compat.patch
    ];

  # nixpkgs 26.01's postPatch matches the old uv command. SPDK 26.05 added
  # USE_SYSTEM_PYTHON and DESTDIR; replace that whole uv prefix so `--system`
  # cannot leak into pip while retaining staged-install path semantics.
  postPatch = ''
    patchShebangs .
    substituteInPlace python/Makefile \
      --replace-fail "uv pip install \$(USE_SYSTEM_PYTHON) --prefix=\$(DESTDIR)\$(CONFIG_PREFIX)" \
                     "python3 -m pip install --no-deps --no-build-isolation --prefix=\$(DESTDIR)\$(CONFIG_PREFIX)"

    # Fail loudly if the initrd compatibility patch was silently skipped.
    grep -q cpu_lock_dir lib/event/app.c
    grep -q initrd-release lib/event/app.c
  '';

  # The 26.01 expression forced AS=nasm, while stdenv otherwise exports AS=as.
  # ISA-L 2.32 treats either as a user-supplied assembler and uses the wrong
  # feature probe. Unset it so native NASM detection uses the correct syntax.
  preConfigure = "unset AS";

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
      help2man
      python3.pkgs.jinja2
      python3.pkgs.pyelftools
      python3.pkgs.tabulate
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
