{
  lib,
  rustPlatform,
  fetchFromGitHub,
  makeWrapper,
}:
rustPlatform.buildRustPackage rec {
  pname = "nvidia_oc";
  version = "0.1.24";

  src = fetchFromGitHub {
    owner = "Dreaming-Codes";
    repo = "nvidia_oc";
    rev = "54f59c3aad68d671dbd670a1ffaa8459419bd258";
    hash = "sha256-PIe4oJndISf6wDxHGQvTeN37cFa+3m6RwmxXRlseePc=";
  };

  cargoHash = "sha256-e6cX9P5dHDOLS06Bx1VuMpH/ilcpyFnHpttG7DDwz8U=";

  nativeBuildInputs = [makeWrapper];

  doCheck = false;

  postInstall = ''
    wrapProgram "$out/bin/nvidia_oc" \
      --prefix LD_LIBRARY_PATH : /run/opengl-driver/lib
  '';

  meta = with lib; {
    description = "CLI tool to overclock NVIDIA GPUs using NVML on Linux";
    homepage = "https://github.com/Dreaming-Codes/nvidia_oc";
    license = licenses.mit;
    mainProgram = "nvidia_oc";
    platforms = platforms.linux;
  };
}
