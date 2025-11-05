{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  protobuf,
  openssl,
  sqlite,
  libclang,
  stdenv,
  darwin,
}:
rustPlatform.buildRustPackage rec {
  pname = "tari-base-node";
  version = "5.0.5";

  src = fetchFromGitHub {
    owner = "tari-project";
    repo = "tari";
    rev = "v${version}";
    hash = "sha256-KtkZ51qEeOr82xpS8Tpn2a3qZ6etgtomH069NsBSKvw=";
  };

  cargoHash = "sha256-xOBdfUuVCEaBYl8/afXvleb6Lj8Z/n3w66prJgAoUsY=";

  nativeBuildInputs = [
    pkg-config
    protobuf
    libclang
  ];

  buildInputs =
    [
      openssl
      sqlite
    ]
    ++ lib.optionals stdenv.isDarwin [
      darwin.apple_sdk.frameworks.Security
      darwin.apple_sdk.frameworks.SystemConfiguration
    ];

  # Build only the base node binary
  buildAndTestSubdir = "applications/minotari_node";

  # Skip tests during build
  doCheck = false;

  # Set environment for bindgen
  LIBCLANG_PATH = "${libclang.lib}/lib";

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
}
