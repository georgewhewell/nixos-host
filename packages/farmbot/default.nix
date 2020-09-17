{
rustPlatform
, pkg-config
, dbus
}:

rustPlatform.buildRustPackage rec {
  pname = "farmbot";
  version = "0.0.1";

  src = ./farmbot;

  buildInputs = [ dbus ];
  nativeBuildInputs = [ pkg-config ];

  cargoSha256 = "1f53b2ql3azgjcl51r8b4qi9w3zr92js4rkkpn91nrw2gc0ndg4z";

}
