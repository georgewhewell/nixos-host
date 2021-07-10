{ stdenv
, sources 
, jdk
, gradle
, libsodium
}:

stdenv.mkDerivation {
    name = "besu";
    src = sources.besu;

    buildInputs = [ jdk gradle libsodium ];
    buildPhase = ''
        patchShebangs gradlew
        ./gradlew build
    '';

}