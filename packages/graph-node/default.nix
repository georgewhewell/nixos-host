{
rustPlatform
, sources
, pkg-config
, openssl
, postgresql
}:

rustPlatform.buildRustPackage rec {
  pname = "graph-node";
  version = sources.graph-node.rev;

  src = sources.graph-node;

  buildInputs = [ openssl postgresql ];
  nativeBuildInputs = [ pkg-config ];

  cargoSha256 = "0v0596080jmkwpap4xr3pm225rryc1xcl93jhkc1kjgmyhi7wpwq";

  doCheck = false;
  
}
