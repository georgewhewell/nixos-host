self: super:

{

  linuxPackages_megous = super.linuxPackagesFor (self.linux_megous);
  linux_megous = super.linux_testing.override {
    argsOverride = rec {
      src = self.sources.linux_megous;
      version = "5.7";
      modDirVersion = "5.7.0";
    };
  };

  linuxPackages_amlogic = super.linuxPackagesFor (self.linux_amlogic);
  linux_amlogic = super.linux_testing.override {
    argsOverride = rec {
      src = self.sources.linux_amlogic;
      version = "5.7";
      modDirVersion = "5.7.0";
      kernelPatches = super.linux_testing.kernelPatches ++ [{
        name = "enable staging media drivers";
        patch = null;
        extraConfig = ''
          STAGING_MEDIA y
        '';
      }];
    };
  };

  linuxPackages_meson_mx = super.linuxPackagesFor (self.linux_meson_mx);
  linux_meson_mx = super.linux_testing.override {
    argsOverride = rec {
      src = self.sources.linux_meson_mx;
      version = "5.7";
      modDirVersion = "5.7.0";
      kernelPatches = super.linux_testing.kernelPatches ++ [{
        name = "disable broken stuff";
        patch = null;
        extraConfig = ''
          WLAN_VENDOR_REALTEK n
          USB_CONN_EXTCON n
        '';
      }];
    };
  };

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
  sunxi-tools = super.sunxi-tools.overrideAttrs(old: {
    version = "master";
    src = self.sources.sunxi-tools;
    nativeBuildInputs = old.nativeBuildInputs ++ [ super.git ];
  });

  # Append local packages
} // (import ../packages { pkgs = super; })
