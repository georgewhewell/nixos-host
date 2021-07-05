{ lib, stdenv, buildGoModule, fetchFromGitHub, sources }:

let
  # A list of binaries to put into separate outputs
  bins = [
    "geth"
  ];

in buildGoModule rec {
  pname = "bsc-ethereum";
  version = sources.bsc.version;

  src = sources.bsc;

  runVend = true;
  vendorSha256 = "10c5iwyrgc4v52vbg2f9rgb9162vna8i2y3q1w673fqz9xgcgd92";

  doCheck = false;

  outputs = [ "out" ] ++ bins;

  # Move binaries to separate outputs and symlink them back to $out
  postInstall = lib.concatStringsSep "\n" (
    builtins.map (bin: "mkdir -p \$${bin}/bin && mv $out/bin/${bin} \$${bin}/bin/ && ln -s \$${bin}/bin/${bin} $out/bin/") bins
  );

  subPackages = [
    "cmd/abidump"
    "cmd/abigen"
    "cmd/bootnode"
    "cmd/checkpoint-admin"
    "cmd/clef"
    "cmd/devp2p"
    "cmd/ethkey"
    "cmd/evm"
    "cmd/faucet"
    "cmd/geth"
    "cmd/p2psim"
    "cmd/puppeth"
    "cmd/rlpdump"
    "cmd/utils"
  ];

}
