{ stdenv, lib, pkgs }:

stdenv.mkDerivation rec {
  version="2015.01";
  name = "fip_create-${version}";

  src = pkgs.fetchFromGitHub {
    owner = "hardkernel";
    repo = "u-boot";
    rev = "odroidc2-v${version}";
    sha256 = "09s0y69ilrwnvqi1g11axsnhylq8kfljwqxdfjifa227mi0kzq37";
  };

  sourceRoot = "source/tools/fip_create";
  /* buildPhase = ''
    cp -rL $src/tools/fip_create ./
    chmod -R +rw fip_create
    cd fip_create && make CC=dsadas
  ''; */
  HOSTCC="${stdenv.cc}/bin/cc";
  extraMakeFlags = [ "HOSTCC=${stdenv.cc}/bin/cc" ];
  installPhase = ''
    mkdir -p $out/bin
    mv fip_create $out/bin/
  '';

  meta = {
    description = "odroid-c2 fip-create tool";
    maintainers = [ stdenv.lib.maintainers.georgewhewell ];
  };
}
