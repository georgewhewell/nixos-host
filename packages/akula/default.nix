{ clang
, cmake
, fetchFromGitHub
, fetchurl
, lib
, llvmPackages
, nodePackages
, perl
, protobuf
, rustPlatform
}:

rustPlatform.buildRustPackage rec {
  pname = "akula";
  version = "d0336c89d3b8901f2d697937d05cb781f4410d69";

  src = fetchFromGitHub {
    owner = "akula-bft";
    repo = "akula";
    rev = "${version}";
    sha256 = "sha256-FZNErtS7c5H9FqPsntAH8PClPr2/xqkqKhrw6QMaiso=";
  };
  cargoSha256 = "sha256-GJvQ3oJtmCmRnjkn/PfO6S3qvEJwpm/Q43cSez7rJHA=";

  postPatch = ''
    # requires .git
    rm build.rs

    # requires nightly
    sed '1i\#![feature(let_else)]\' -i src/lib.rs
  '';

  VERGEN_BUILD_SEMVER = "0.1.0";
  VERGEN_GIT_BRANCH = "master";
  VERGEN_GIT_SHA_SHORT = "d0336c";
  VERGEN_GIT_COMMIT_DATE = "1970-01-01";
  VERGEN_CARGO_TARGET_TRIPLE = rustPlatform.rust.cargo.system;
  VERGEN_RUSTC_SEMVER = rustPlatform.rust.cargo.version;

  nativeBuildInputs = [ clang cmake perl protobuf ];

  LIBCLANG_PATH = "${llvmPackages.libclang.lib}/lib";

  cargoBuildFlags = [
    "--bin=akula"
  ];

  doCheck = false;

  meta = with lib; {
    description = "Next-generation implementation of Ethereum protocol written in Rust, based on Erigon architecture.";
    homepage = "https://akula.app/";
    license = licenses.agpl3;
    maintainers = with maintainers; [ georgewhewell ];
  };
}
