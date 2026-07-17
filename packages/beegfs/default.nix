{ stdenv
, lib
, fetchFromGitHub
, pkg-config
, libnl
, openssl
, rdma-core
, util-linux
, curl
, xfsprogs
}:

# BeeGFS 8 userspace: meta/storage/mon daemons, fsck and the beegfs_ib RDMA
# backend (dlopen'd at runtime, links rdma-core). Built with upstream's
# Makefiles — the in-tree CMake build is bit-rotted at 8.4.0 (references
# removed sources). The management daemon and `beegfs` CTL live in separate
# repos (beegfs-rust, beegfs-go) and are packaged separately. The client
# kernel module is in ./client-module.nix.
stdenv.mkDerivation rec {
  pname = "beegfs";
  # master; the 8.4.0 tag content diverges from the release commit on master
  # (upstream squashes releases) and lacks the base/ directory entirely.
  version = "8.4.0-unstable-2026-07-15";

  src = fetchFromGitHub {
    owner = "ThinkParQ";
    repo = "beegfs";
    rev = "775cf9291b0b690a729221d67eb01bc3579023c0";
    hash = "sha256-2ihlQ6dCfbivP+MnaIhBkfQHeNgvRJhkX4M8hvZdvuQ=";
  };

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ libnl openssl rdma-core util-linux curl xfsprogs ];

  # define-dep-lib records raw `pkg-config --libs` output as make
  # *prerequisites*, which end up in the `ar -rcs $@ $^` archive command. On
  # non-/usr systems pkg-config emits -L/nix/store/... and ar chokes on it
  # (Debian's bare -lfoo is silently eaten by ar's legacy `l` option, so
  # upstream never notices). Keep only real file deps in the dep list.
  postPatch = ''
    substituteInPlace build/Makefile \
      --replace-fail \
        '$(eval _DEP_LIB_DEPS[$(strip $1)] = $(strip $3))' \
        '$(eval _DEP_LIB_DEPS[$(strip $1)] = $(strip $(filter-out -L% -l%,$3)))'
  '';

  enableParallelBuilding = true;

  makeFlags = [
    # No .git in the fetched tarball, so the version can't be derived.
    "BEEGFS_VERSION=${version}"
    "PREFIX="
    "DESTDIR=${placeholder "out"}"
    # The Makefile probes `ar -TM` and appends -T (thin archives) on success,
    # but current binutils repurposed -T; command-line AR= overrides the +=.
    "AR=ar"
  ];

  buildFlags = [ "daemons" "utils" ];

  # Upstream `install` also wants client-install (kernel module); install the
  # userspace components individually instead.
  installTargets = [ "daemons-install" "utils-install" "common-install" ];

  meta = {
    description = "BeeGFS parallel filesystem (userspace daemons and tools)";
    homepage = "https://www.beegfs.io";
    license = lib.licenses.unfreeRedistributable; # BeeGFS EULA (source-available)
    platforms = lib.platforms.linux;
  };
}
