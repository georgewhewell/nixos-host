self: super:

{

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

  tvheadend = super.tvheadend.overrideAttrs (old: {
    patches = [ ./tvheadend.patch ];
    preConfigure = ''
      substituteInPlace src/input/mpegts/scanfile.c \
          --replace 'path = "/usr/share/dvb"' 'path = "${self.dtv-scan-tables}/share/dvb"'

      ${old.preConfigure}
    '';

  });

  firmwareLinuxNonfree = super.firmwareLinuxNonfree.overrideAttrs(old: {
    src = super.fetchurl {
      url = "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/snapshot/linux-firmware-20200619.tar.gz";
      sha256 = "1i8gnmsppq531mzmq9z72w2h4wyn6dvynzvbr6xsqp2iqw0sjsi5";
    };
    outputHash = "1cnl2f5s42pybxmlpzqhjwpx33fy3na6xwnfxdk8sv7s6nzkwbiv";
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

  # Append local packages
} // (import ../packages { pkgs = super; })
