{ stdenv
, lib
, fetchFromGitHub
, makeWrapper
, dnsutils
, google-cloud-sdk
, curl
}:

stdenv.mkDerivation rec {
  pname = "public-ip-sync-google-clouddns";
  version = "master";

  src = fetchFromGitHub
    {
      owner = "headcr4sh";
      repo = "public-ip-sync-google-clouddns";
      rev = "master";
      sha256 = "sha256-knxZJClQi1bCIbyokF0o8gmoiCEwWNkAbo3bzUjwv/A=";
    };

  installPhase = ''
    mkdir -p $out/bin
    cp public-ip-sync-google-clouddns.sh $out/bin
    wrapProgram "$out/bin/public-ip-sync-google-clouddns.sh" \
     --prefix PATH : "${dnsutils}/bin" \
     --prefix PATH : "${google-cloud-sdk}/bin" \
     --prefix PATH : "${curl}/bin"
  '';

  buildInputs = [ makeWrapper ];

}
