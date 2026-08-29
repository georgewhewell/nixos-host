{
  stdenvNoCC,
  python3,
  makeWrapper,
}:
stdenvNoCC.mkDerivation {
  pname = "vpp-ipv6-publication-sync";
  version = "1";
  src = ./vpp-ipv6-publication-sync.py;
  dontUnpack = true;
  nativeBuildInputs = [makeWrapper];

  installPhase = ''
    runHook preInstall
    install -Dm0444 "$src" "$out/libexec/vpp-ipv6-publication-sync.py"
    makeWrapper ${python3}/bin/python3 "$out/bin/vpp-ipv6-publication-sync" \
      --add-flags "$out/libexec/vpp-ipv6-publication-sync.py"
    runHook postInstall
  '';
}
