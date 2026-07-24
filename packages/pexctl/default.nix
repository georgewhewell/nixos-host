{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "pexctl";
  version = "0.1.0";

  src = ./.;
  cargoLock.lockFile = ./Cargo.lock;

  meta = {
    description = "Open CLI for Broadcom/PLX PEX switch configuration";
    homepage = "https://github.com/robcohen/nixos-config";
    license = lib.licenses.mit;
    mainProgram = "pexctl";
    platforms = lib.platforms.linux;
  };
}
