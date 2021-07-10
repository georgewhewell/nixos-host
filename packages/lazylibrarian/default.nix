{ fetchurl, python3Packages, lib, fetchFromGitLab }:

with python3Packages;

buildPythonApplication rec {
  pname = "lazylibrarian";
  version = "3.0.1";

  src = fetchFromGitLab {
    owner = "LazyLibrarian";
    repo = "LazyLibrarian";
    rev = "master";
    sha256 = "15gdjmlcrzc8269nq8lr3cx82s5hmx7wxjrwv5mwrxm13ysgslzd";
  };

  format = "other";

  postPatch = ''
    substituteInPlace LazyLibrarian.py --replace "dirname(os.path.abspath(__file__))" "os.path.join(dirname(os.path.abspath(__file__)), '../${python.sitePackages}')"
  '';

  installPhase = ''
    mkdir -p $out/bin/
    mkdir -p $out/${python.sitePackages}/

    cp -r * $out/${python.sitePackages}/
    cp -r data $out/bin/

    cp LazyLibrarian.py $out/bin/lazylibrarian
    chmod +x $out/bin/*
  '';

  postFixup = ''
    wrapProgram "$out/bin/lazylibrarian" --set PYTHONPATH "$PYTHONPATH:$out/${python.sitePackages}"
  '';

  meta = {
    description = "Automatic movie downloading via NZBs and torrents";
    license     = lib.licenses.gpl3;
    homepage    = "https://couchpota.to/";
    maintainers = with lib.maintainers; [ fadenb ];
  };
}
