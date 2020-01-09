self: super:

{

  linuxPackages_4_19 = let
    media = super.fetchFromGitHub rec {
      name = repo;
      owner = "tbsdtv";
      repo = "linux_media";
      rev = "e71fb1797e3c89d90a5cb55523f50e5918276698";
      sha256 = "1zy700rkm7blq5jc273c4n7msbidyg20snsr9hpfrd4lrggpqwxg";
    };
    build = super.fetchFromGitHub rec {
      name = repo;
      owner = "tbsdtv";
      repo = "media_build";
      rev = "ef3744c6108e781887ff3ed0ec930eba0ca8835f";
      sha256 = "0v53iyj9cpa15psi2y7r3lpqf2pahb858nx4qnbrlgaxfrqps4l0";
    };
    in super.linuxPackages_4_19 // {
    tbs = super.linuxPackages_4_19.tbs.overrideAttrs (old: {
      srcs = [ media build ];
      preConfigure = ''
        # dont need
        sed -i "/DVB_SAA716X_FF/a disable_config('MEDIA_PCI_SUPPORT');" v4l/scripts/make_kconfig.pl

        # fails build (perhaps only VIN)
        sed -i "/DVB_SAA716X_FF/a disable_config('VIDEO_RCAR_DRIF');" v4l/scripts/make_kconfig.pl
        sed -i "/DVB_SAA716X_FF/a disable_config('VIDEO_RCAR_CSI2');" v4l/scripts/make_kconfig.pl
        sed -i "/DVB_SAA716X_FF/a disable_config('VIDEO_RCAR_VIN');" v4l/scripts/make_kconfig.pl

        # broken
        sed -i "/DVB_SAA716X_FF/a disable_config('VIDEO_TDA1997X');" v4l/scripts/make_kconfig.pl

        # nothing good comes of mediatek
        sed -i "/DVB_SAA716X_FF/a disable_config('VIDEO_MEDIATEK_VPU');" v4l/scripts/make_kconfig.pl
        sed -i "/DVB_SAA716X_FF/a disable_config('VIDEO_MEDIATEK_VCODEC');" v4l/scripts/make_kconfig.pl
        sed -i "/DVB_SAA716X_FF/a disable_config('VIDEO_MEDIATEK_MDP');" v4l/scripts/make_kconfig.pl
        sed -i "/DVB_SAA716X_FF/a disable_config('IR_MTK');" v4l/scripts/make_kconfig.pl

        # missing includes
        sed -i "/ti_wilink_st/a TARFILES += include/linux/interconnect.h" linux/Makefile

        # meson-canvas.h fails
        sed -i "/DVB_SAA716X_FF/a disable_config('IR_MESON');" v4l/scripts/make_kconfig.pl
        sed -i "/DVB_SAA716X_FF/a disable_config('VIDEO_MESON_G12A_AO_CEC');" v4l/scripts/make_kconfig.pl
        sed -i "/DVB_SAA716X_FF/a disable_config('VIDEO_MESON_AO_CEC');" v4l/scripts/make_kconfig.pl
        sed -i "/DVB_SAA716X_FF/a disable_config('VIDEO_QCOM_VENUS');" v4l/scripts/make_kconfig.pl

        sed -i "/DVB_SAA716X_FF/a disable_config('VIDEO_SUN4I_CSI');" v4l/scripts/make_kconfig.pl
        sed -i "/DVB_SAA716X_FF/a disable_config('VIDEO_SUN6I_CSI');" v4l/scripts/make_kconfig.pl

        make dir DIR=../${media.name}

        # make module in parallel
        sed -i "/MYCFLAGS :=/s/.*/ MYCFLAGS := -j$NIX_BUILD_CORES/" v4l/Makefile
      '';

    });
  };

  tvheadend = super.tvheadend.overrideAttrs(old: {
      preConfigure = ''
        substituteInPlace src/input/mpegts/scanfile.c \
            --replace 'path = "/usr/share/dvb"' 'path = "${self.dtv-scan-tables}/share/dvb"'

        ${old.preConfigure} 
      '';
    
  });

  steam = null;

  waybar = super.waybar.override { pulseSupport = true; };

  radarr = super.radarr.overrideAttrs(old: rec {
    version = "0.2.0.1450";
    src = super.fetchurl {
      url = "https://github.com/Radarr/Radarr/releases/download/v${version}/Radarr.develop.${version}.linux.tar.gz";
      sha256 = "1sknq6fifpmgzryr07dnriaw2x425v2zxdcqzm65viw5p5j9xh00";
    };
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
