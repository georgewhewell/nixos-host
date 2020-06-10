{ stdenv, sources }:

stdenv.mkDerivation {
  name = "dtv-scan-tables";
  version = sources.dtv_scan_tables.rev;

  src = sources.dtv_scan_tables;

  buildPhase = ''
    mkdir -p $out/share/dvb
  '';

  installPhase = ''
    cp -rv * $out/share/dvb
  '';

}
