{ stdenv
, fetchFromGitHub
, perl
}:

stdenv.mkDerivation rec {
  pname = "hsphfpd";
  version = "prototype";

  src = fetchFromGitHub {
    owner  = "pali";
    repo   = "hsphfpd-prototype";
    rev    = version;
    sha256 = "0aslz2sc5i93k6waxg8796j3hziggk3cdcs22r17a2lhc49yaa2v";
  };

  propagatedBuildInputs = [
    (perl.withPackages (ps: with ps; [ NetDBus ]))
  ];

  installPhase = ''
    mkdir -p $out/bin $out/etc/dbus-1/system.d
    install -D hsphfpd.pl $out/bin/
    install -D org.hsphfpd.conf $out/etc/dbus-1/system.d/
  ''; 

}
