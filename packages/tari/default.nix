{
  lib,
  rust-bin,
  makeRustPlatform,
  fetchFromGitHub,
  pkg-config,
  protobuf,
  openssl,
  sqlite,
  libclang,
  cmake,
  automake,
  autoconf,
  autoconf-archive,
  gnum4,
  libtool,
  stdenv,
  darwin,
  targetNetwork ? "mainnet",
}: let
  version = "5.1.0";
  src = fetchFromGitHub {
    owner = "tari-project";
    repo = "tari";
    rev = "v${version}";
    hash = "sha256-61JF/+qc1647CAqYZZd6WYRGUd8g5YJz0mlmWwzTlTE=";
    fetchSubmodules = true;
  };
  # src = "${repoSrc}/applications/minotari_node";
  rust-toolchain = rust-bin.fromRustupToolchainFile "${src}/rust-toolchain.toml";
  rustPlatform = makeRustPlatform {
    rustc = rust-toolchain;
    cargo = rust-toolchain;
  };
  patchedCargoLockFile = builtins.path {
    name = "tari-cargo-lock-patched";
    path = ./Cargo.lock.patched;
  };
  patchedCargoLock = builtins.readFile patchedCargoLockFile;
in
  rustPlatform.buildRustPackage (finalAttrs: {
    pname = "tari-base-node";
    cargoLock = {
      lockFileContents = patchedCargoLock;
      outputHashes = {
        "ledger-transport-0.11.0" = "sha256-2hUNLsJEFzABowpnDkJCtqr45dEF07iL77+ijEIBkZo=";
        "ledger-transport-hid-0.11.0" = lib.fakeHash;
        "liblmdb-sys-0.2.3" = "sha256-Y+KRHyR632gD7obckcdw1h9rh6jb9xLVv/7j2nG/yZI=";
      };
    };
    # cartgo
    inherit src version;
    # cargoLock = {
    #   lockFile = "${src}/Cargo.lock";
    #   outputHashes = {
    #     "liblmdb-sys-0.2.3" = "sha256-Y+KRHyR632gD7obckcdw1h9rh6jb9xLVv/7j2nG/yZI=";
    #     "ledger-transport-0.11.0" = "sha256-2hUNLsJEFzABowpnDkJCtqr45dEF07iL77+ijEIBkZo=";
    #   };
    # };
    buildInputs = [openssl sqlite];
    nativeBuildInputs = [cmake protobuf autoconf autoconf-archive gnum4 automake libtool];
    # checkInputs =  [cargo-audit cargo-deny cargo-outdated];

    # nativeBuildInputs = [
    #   pkg-config
    #   protobuf
    #   libclang
    # ];

    # Build only the base node binary
    buildAndTestSubdir = "applications/minotari_node";

    patches = [];

    # Ensure Cargo.lock in source matches vendored lock for cargoSetup
    postPatch = ''
      cp ${patchedCargoLockFile} Cargo.lock
    '';

    # Skip tests during build
    # doCheck = false;

    TARI_TARGET_NETWORK = targetNetwork;

    # Set environment for bindgen
    # LIBCLANG_PATH = "${libclang.lib}/lib";

    # The workspace uses patches that might need LMDB configuration
    # For now, we'll use the default features
    buildFeatures = ["default"];

    meta = with lib; {
      description = "Tari protocol base node (Minotari node)";
      homepage = "https://www.tari.com";
      license = licenses.bsd3;
      maintainers = [];
      mainProgram = "minotari_node";
      platforms = platforms.unix;
    };
  })
