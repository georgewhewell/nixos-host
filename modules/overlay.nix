self: super:

{

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

  /*
  firmwareLinuxNonfree = super.firmwareLinuxNonfree.overrideAttrs(old: {
    src = super.fetchurl {
      url = "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/snapshot/linux-firmware-20201218.tar.gz";
      sha256 = "0hjinnj29h2vr44sxxmgankdlhsxpv5rjgk3xwb9l7hjcfwv6rcr";
    };
    outputHash = "1p7vn2hfwca6w69jhw5zq70w44ji8mdnibm1z959aalax6ndy146";
  });
  */

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
