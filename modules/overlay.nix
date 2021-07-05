self: super:

{

  ddcutil = super.ddcutil.overrideAttrs (old: {
    src = self.sources.ddcutil;
  });

  dfu-util = super.dfu-util.overrideAttrs (old: {
    src = super.fetchFromGitHub {
      owner = "riscv-mcu";
      repo = "gd32-dfu-utils";
      rev = "master";
      sha256 = "0hyzbwx29qws5bpp3gw161z6x1bacsnq1lw0v5ja8z4nr9mj9ds7";
    };
  });

  gattool = super.bluez.overrideAttrs (
    old: {
      name = "gattool";
      configureFlags = (old.configureFlags or [ ]) ++ [ "--enable-deprecated" ];
      makeFlags = [ "attrib/gatttool" ];
      doCheck = false;
      outputs = [ "out" ];
      installPhase = ''
        install -D attrib/gatttool $out/bin/gatttool
      '';
    }
  );

  kodiPlain = super.kodiPlain.overrideAttrs (old: {
    buildInputs = old.buildInputs ++ [ super.xorg.libXext.dev super.xorg.libXrandr.dev ];
  });

  waybar = super.waybar.override { pulseSupport = true; };
  sunxi-tools = super.sunxi-tools.overrideAttrs (old: {
    version = "master";
    src = self.sources.sunxi-tools;
    nativeBuildInputs = old.nativeBuildInputs ++ [ super.git ];
  });

  avrdude = super.avrdude.overrideAttrs(old: {
    configureFlags = old.configureFlags ++ [
      "--enable-linuxgpio"
    ];

    postPatch = ''
      substituteInPlace libavrdude.h \
        --replace "PIN_MAX     31" "PIN_MAX     255"
    '';
  });

  esphome = super.esphome.overrideAttrs(old: rec {
    src = super.fetchFromGitHub {
      owner = "buxtronix";
      repo = "esphome";
      rev = "am43";
      sha256 = "1mki3jz66xx6iy23dxp3xqgvd1ry6lp8q2kxhiyav59f43hrjxa5";
    };
  });

  metabase = super.metabase.overrideAttrs(old: rec {
    version = "0.37.6";
    src = super.fetchurl {
      url = "https://downloads.metabase.com/v${version}/metabase.jar";
      sha256 = "1bzc2dv7apa1b6gd2qlr3nmxk2cgq34wf0yp8jx419wv8xq5hrqr";
    };
    installPhase = ''
      makeWrapper ${super.jre8}/bin/java $out/bin/metabase --add-flags "-jar $src"
    '';
  });

  go-ethereum = super.go-ethereum.overrideAttrs(old: rec {
    src = self.sources.go-ethereum;
    vendorSha256 = null;
  });

  # Append local packages
} // (import ../packages { pkgs = super; })
