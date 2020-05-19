{ rustPlatform, lib }:

rustPlatform.buildRustPackage rec {
  pname = "natures_prophet";
  version = "0.0.1";

  src = ./.;

  cargoSha256 = "13n3mlbzv9wf8gpp0qxy8vcqisby68kj9jr4hzvfs299shf1k2ng";

}
