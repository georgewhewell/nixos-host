{ rustPlatform }:

rustPlatform.buildRustPackage rec {
  pname = "weather";
  version = "0.0.1";

  src = ./weather;

  cargoSha256 = "117bkhpfdz87bffb3ga65lhss91fbda7h5napvvfq2kjn3y5zlbk";

}
