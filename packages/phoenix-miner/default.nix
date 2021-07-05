{
  stdenv
, sources
, gcc-unwrapped
, pciutils
, autoPatchelfHook
, makeWrapper
, addOpenGLRunpath
}:

stdenv.mkDerivation {
  pname = "phoenix-miner";
  version = sources.PhoenixMiner.rev;

  src = sources.PhoenixMiner;

  buildInputs = [ pciutils gcc-unwrapped autoPatchelfHook makeWrapper ];
  /* propagatedBuildInputs = [ ocl-icd ]; */

  installPhase = ''
    mkdir -p $out/bin
    cp PhoenixMiner config.txt $out/bin/
  '';

  /* postInstall = ''
    wrapProgram $out/bin/PhoenixMiner --prefix LD_LIBRARY_PATH : /run/opengl-driver/lib
  ''; */
}
