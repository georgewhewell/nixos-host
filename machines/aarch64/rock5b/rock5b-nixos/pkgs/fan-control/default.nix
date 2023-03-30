{
  stdenv,
  src,
  ...
}:
stdenv.mkDerivation {
  name = "fan-control";
  inherit src;
  installPhase = ''
    install -Dm 555 fan-control -t $out/bin
  '';
}
