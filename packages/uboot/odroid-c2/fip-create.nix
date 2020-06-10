{ stdenv, lib, pkgs, sources }:

stdenv.mkDerivation rec {
  version = "2015.01";
  name = "fip_create-${version}";

  src = sources.u-boot-odroid-c2;

  sourceRoot = "source/tools/fip_create";
  /* buildPhase = ''
    cp -rL $src/tools/fip_create ./
    chmod -R +rw fip_create
    cd fip_create && make CC=dsadas
  ''; */
  HOSTCC = "${stdenv.cc}/bin/cc";
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
