{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
buildGoModule rec {
  pname = "apple-health-ingester";
  version = "0.5.0";

  src = fetchFromGitHub {
    owner = "irvinlim";
    repo = "apple-health-ingester";
    rev = "v${version}";
    hash = "sha256-jc5z6F3tez1BFyQMAonDfI3fgd4YmidsTuDLxKrmm50=";
  };

  vendorHash = "sha256-5lbEamyfDNCpY509+YpBbJRJHazc8WsgeNpZoNCsfqw=";

  subPackages = ["cmd/ingester"];

  ldflags = [
    "-s"
    "-w"
  ];

  meta = {
    description = "Ingests data from Apple Health exported via Health Auto Export iOS app";
    homepage = "https://github.com/irvinlim/apple-health-ingester";
    license = lib.licenses.mit;
    maintainers = [];
    mainProgram = "ingester";
  };
}
