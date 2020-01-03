self: super:

{
  steam = null;

  waybar = super.waybar.override { pulseSupport = true; };

  radarr = super.radarr.overrideAttrs(old: rec {
    version = "0.2.0.1450";
    src = super.fetchurl {
      url = "https://github.com/Radarr/Radarr/releases/download/v${version}/Radarr.develop.${version}.linux.tar.gz";
      sha256 = "1sknq6fifpmgzryr07dnriaw2x425v2zxdcqzm65viw5p5j9xh00";
    };
  });
  
  tvheadend = super.tvheadend.overrideAttrs (old: {
    propagatedBuildInputs = [ self.dtv-scan-tables ];
  });

  libfprint = super.libfprint.overrideAttrs (old: {
    src = super.fetchFromGithub {
      owner = "nmikhailov";
      repo = "Validity90";
      rev = "00ac6ab7f54b012a8a0627fb389bd62ebf14c4fb";
      sha256 = "0wq8lrial1khc0kv34g2n7wbl9bf9m3vfk29d51g6r0hg3vzp49l";
    };
  });

  validity90 = super.stdenv.mkDerivation {
    name = "validity90";
    version = "unstable";
    src = super.fetchFromGitHub {
      owner = "nmikhailov";
      repo = "Validity90";
      rev = "00ac6ab7f54b012a8a0627fb389bd62ebf14c4fb";
      sha256 = "04hdfp80ckwjljk5np358rx3vcfhf2fqvs9b7savsazrgm2p955l";
    };
    sourceRoot = "source/prototype/";
    buildInputs = with super; [
      pkgconfig
      glib.dev
      gnutls
      libusb
      libgcrypt
      libpng
      nss
      openssl.dev
    ];
    installPhase = ''
      mkdir -p $out/bin
      cp prototype $out/bin/validity90
    '';
  };

  auto-rotate = super.stdenv.mkDerivation {
    name = "auto-rotate";
    version = "auto-rotate";

    src = super.fetchFromGitHub {
      owner = "mrquincle";
      repo = "yoga-900-auto-rotate";
      rev = "master";
      sha256 = "0qcbixclw8863gjjlildwwydpa1n9hw5260v1kfb0x1jx0p8axl2";
    };

    buildInputs = with super; [
      iio-sensor-proxy
      pkgconfig
      systemd.dev
      glib
      x11
      xorg.libXi
      xorg.libXrandr
    ];

    buildPhase = ''
      substituteInPlace auto-rotate.c \
        --replace "= reflectX" "= rotate180"
      make
    '';

    installPhase = ''
      mkdir -p $out/bin
      cp auto-rotate $out/bin/
    '';
  };

  sunxi-tools = super.sunxi-tools.overrideAttrs(old: {
    version = "2019-06-20";
    src = super.fetchFromGitHub {
      owner = "linux-sunxi";
      repo = "sunxi-tools";
      rev  = "42ffc5f76a30ecd10c89989a7fe100feb15ce16e";
      sha256 = "005cma0nm5mwdb4wn8n4351n93d0b1p4y2bssrfj9fjvba7fl5q1";
    };
    nativeBuildInputs = old.nativeBuildInputs ++ [ super.git ];
  });

  # Append local packages
} // (import ../packages { pkgs = super; })
