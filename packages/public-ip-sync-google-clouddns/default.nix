{
stdenv
, sources
, makeWrapper
, dnsutils
, google-cloud-sdk
, curl
}:

stdenv.mkDerivation rec {
  pname = "public-ip-sync-google-clouddns";
  version = "master";

  src = sources.public-ip-sync-google-clouddns;

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