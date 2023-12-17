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
  waybar = super.waybar.override { pulseSupport = true; };

  openrgb = super.openrgb.overrideAttrs (old: rec {
    src = self.sources.openrgb;
    buildInputs = old.buildInputs ++ [ super.mbedtls ];
  });

  steam = super.hello;

  # Append local packages
} // (import ../packages { pkgs = super; })
