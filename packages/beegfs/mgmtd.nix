{ lib
, rustPlatform
, fetchFromGitHub
}:

# BeeGFS 8 management service (rewritten in Rust, lives in beegfs-rust).
# State is a bundled-rusqlite database, so no external sqlite needed.
rustPlatform.buildRustPackage rec {
  pname = "beegfs-mgmtd";
  version = "8.4.0-unstable-2026-07-14";

  src = fetchFromGitHub {
    owner = "ThinkParQ";
    repo = "beegfs-rust";
    rev = "e3495286010a7d6b9c2caf98fa8da6f916f1ddb1";
    hash = "sha256-vzVUeo8UODMqOxq02fSWqXEnoIFsz2S35WxzyD6AuWQ=";
  };

  cargoHash = "sha256-Uw3I1ecPLYDzdbDqYYCvv6hUrL6jHPht1YIpQf0Buwo=";

  cargoBuildFlags = [ "-p" "mgmtd" ];
  cargoTestFlags = [ "-p" "mgmtd" ];

  # mgmtd reports option_env!("VERSION"), "undefined" if unset. Other nodes
  # compare versions during handshake, so keep it a plausible semver.
  env.VERSION = "8.4.0";

  meta = {
    description = "BeeGFS management service";
    homepage = "https://github.com/ThinkParQ/beegfs-rust";
    license = lib.licenses.unfreeRedistributable; # BeeGFS EULA
    platforms = lib.platforms.linux;
    mainProgram = "beegfs-mgmtd";
  };
}
