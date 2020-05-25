self: super:

{

  linuxPackages_head = super.linuxPackagesFor (super.linux_testing.override {
    argsOverride = rec {
      src = super.fetchurl {
    	  url = "https://git.kernel.org/torvalds/t/linux-${version}.tar.gz";
    	  sha256 = "1xkdvx6msf0wsqxbxjiimcjlzk51ra05ac3n1mi23y27hbxpndmj";
      };
      version = "5.7-rc1";
      modDirVersion = "5.7.0-rc1";
    };
  });

  linuxPackages_megous = super.linuxPackagesFor (super.linux_testing.override {
    argsOverride = rec {
      src = super.fetchFromGitHub {
        owner = "megous";
        repo = "linux";
        rev = "orange-pi-5.7";
        sha256 = "0i0qjn5pyg18n7w8cnvmyil72k3n46zzxaaj60h0yysp8bliy604";
      };
      version = "5.7-rc5";
      modDirVersion = "5.7.0-rc5";
    };
  });

  _pulseaudio = super.pulseaudio.overrideAttrs(old: {
    patches = [
      ./pulseaudio.patch
    ];
  });

  gattool = super.bluez.overrideAttrs (
    old: {
      name = "gattool";
      configureFlags = (old.configureFlags or []) ++ [ "--enable-deprecated" ];
      makeFlags = [ "attrib/gatttool" ];
      doCheck = false;
      outputs = [ "out" ];
      installPhase = ''
        install -D attrib/gatttool $out/bin/gatttool
      '';
    }
  );

  linuxPackages_megous_5_6 = super.linuxPackagesFor (super.linux_testing.override {
    argsOverride = rec {
      src = super.fetchFromGitHub {
        owner = "megous";
        repo = "linux";
        rev = "orange-pi-5.6";
    	  sha256 = "0hvcndbrkmaqdydyvlxvwkxb28vl0js98zhd52r0d397lzck5fp1";
      };
      version = "5.6.5";
      modDirVersion = "5.6.5";
    };
  });

  # broken; stops hydra build
  darcs = null;
  
  kodiPlain = super.kodiPlain.overrideAttrs (old: {
    buildInputs = old.buildInputs ++ [ super.xorg.libXext.dev super.xorg.libXrandr.dev];
  });

  tvheadend = super.tvheadend.overrideAttrs(old: {
      patches = [ ./tvheadend.patch ];
      preConfigure = ''
        substituteInPlace src/input/mpegts/scanfile.c \
            --replace 'path = "/usr/share/dvb"' 'path = "${self.dtv-scan-tables}/share/dvb"'

        ${old.preConfigure}
      '';

  });

  waybar = super.waybar.override { pulseSupport = true; };

  radarr = super.radarr.overrideAttrs(old: rec {
    version = "0.2.0.1450";
    src = super.fetchurl {
      url = "https://github.com/Radarr/Radarr/releases/download/v${version}/Radarr.develop.${version}.linux.tar.gz";
      sha256 = "1sknq6fifpmgzryr07dnriaw2x425v2zxdcqzm65viw5p5j9xh00";
    };
  });

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
    patches = [
      ../packages/patches/sunxi-fel-disablecrc.patch
    ];
  });

  # Append local packages
} // (import ../packages { inherit super; })
