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
}:

# nixpkgs' SPDK 26.01 package currently links against a newer external DPDK
# than SPDK accepts at runtime.  Use the DPDK revision vendored and tested by
# the SPDK release, and enable the ublk target needed to put kernel XFS above
# an SPDK bdev.
spdk.overrideAttrs (old: {
  pname = "spdk-ublk";

  buildInputs =
    builtins.filter (input: input != dpdk) (old.buildInputs or [ ])
    ++ [
      liburing
      rdma-core
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
