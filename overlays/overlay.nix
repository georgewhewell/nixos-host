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

  /*
    jellyfin-ffmpeg = super.jellyfin-ffmpeg.overrideAttrs (old: {
    src = super.fetchFromGitHub {
    owner = "jellyfin";
    repo = "jellyfin-ffmpeg";
    rev = "master";
    sha256 = "sha256-jMd7tEEfiHqTp4q8c6EvbjL0KyJ6ucj4ZNrKOJLJ1Mc=";
    };
    });
  */
  foundry-bin = super.foundry-bin.overrideAttrs (o: {
    installCheckPhase = "";
  });

  # Append local packages
} // (import ../packages { pkgs = super; })
