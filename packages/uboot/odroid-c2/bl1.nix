{ stdenv, fetchurl, bc, dtc, python2, hostPlatform }:

let
  fetchBl1 = { ramSpeed, sha256 }:
    stdenv.mkDerivation (rec {
      name = "bl1-odroid-c2-${ramSpeed}";
      src = fetchurl {
        url = "https://dn.odroid.com/S905/BootLoader/ODROID-C2/bl1.bin.hardkernel.${ramSpeed}";
        sha256 = sha256;
      };

      phases = [ "installPhase" ];
      installPhase = ''
        cp $src $out
      '';

      dontStrip = true;

      meta = {
        description = "odroid-c2 bl1 (${ramSpeed} MHz)";
        maintainers = [ stdenv.lib.maintainers.georgewhewell ];
      };
  });
in rec {
  inherit fetchBl1;
  ram1104 = fetchBl1 rec {
    ramSpeed = "1104";
    sha256 = "1yln8jc5k2hghv913dq17a2jngjyfp1kjyg9yfc3wdssdc1mfm1j";
  };
  ram912 = fetchBl1 rec {
    ramSpeed = "912";
    sha256 = "03kl1bn9h2nj3fx82n1hfvvq6svc7xg9j3ppab9lsggms2k1majx";
  };
  ram792 = fetchBl1 rec {
    ramSpeed = "792";
    sha256 = "0flmm2gyimskym9li4nk1njmlyabd0y7gfwpm49ksv9fh3bh46wr";
  };
  ram408 = fetchBl1 rec {
    ramSpeed = "408";
    sha256 = "13nfk85xnxpidbxdxcf383512bfrn34l1mh2fvch1bpwy5ir7dgk";
  };
  default = ram1104;

}
