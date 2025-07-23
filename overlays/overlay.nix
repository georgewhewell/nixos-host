self: super:
{
  # spotify = super.spotify.overrideAttrs (oldAttrs: {
  #   src = super.fetchurl {
  #     url = "https://download.scdn.co/SpotifyARM64.dmg";
  #     sha256 = "sha256-a3LPFX3/f58fuaEJmzcpsgI27yTaRltwftwOuJBN+nQ=";
  #   };
  # });

  wakiki-fw = super.stdenvNoCC.mkDerivation {
    name = "wakiki-firmware";
    src = ../packages/wakiki-fw;

    installPhase = ''
      echo $(ls -la)
      mkdir -p $out/lib/firmware/ath12k/QCN9274/hw2.0
      cp -r * $out/lib/firmware/ath12k/QCN9274/hw2.0/
      cp regdb.bin $out/lib/firmware/regdb.bin
    '';
  };

  ath12k-fw = super.stdenv.mkDerivation {
    name = "ath12k-firmware";

    src = super.fetchFromGitLab {
      domain = "git.codelinaro.org";
      owner = "clo";
      repo = "ath-firmware/ath12k-firmware";
      rev = "5f5f6d6585e0dc3fd32dae8223a8faf5349e6609";
      hash = "sha256-MwLQpfLAQ2SFqHdxr6CVPT8fnA6mozjgqCcqZFPHfX8=";
    };
  };
}
