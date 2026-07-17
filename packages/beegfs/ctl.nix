{ lib
, buildGoModule
, fetchFromGitHub
}:

# BeeGFS 8 command-line tool (`beegfs`), from the beegfs-go repo.
buildGoModule rec {
  pname = "beegfs-ctl";
  version = "8.4.0-unstable-2026-07-13";

  src = fetchFromGitHub {
    owner = "ThinkParQ";
    repo = "beegfs-go";
    rev = "f005af60d9f612871d6e01969ab0d2819d61774e";
    hash = "sha256-kZOiszDsonk6XESLFRYWPJNRVH3aaVNXt1z3X+ig4nU=";
  };

  # HEAD bumped the go directive to 1.26.5 (stdlib CVE housekeeping, no
  # language change); nixpkgs is at 1.26.3.
  postPatch = ''
    substituteInPlace go.mod --replace-fail "go 1.26.5" "go 1.26.3"
  '';

  vendorHash = "sha256-gl+ijvVpbNZK9QCCx8Ya7wAo9Ui1M3dElBwPJiYAQkk=";

  subPackages = [ "ctl/cmd/beegfs" ];

  ldflags = [ "-s" "-w" ];

  meta = {
    description = "BeeGFS command-line management tool";
    homepage = "https://github.com/ThinkParQ/beegfs-go";
    license = lib.licenses.unfreeRedistributable; # BeeGFS EULA
    platforms = lib.platforms.linux;
    mainProgram = "beegfs";
  };
}
