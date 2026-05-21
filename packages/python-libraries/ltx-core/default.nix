{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  setuptools,
  torch,
  torchaudio,
  einops,
  numpy,
  transformers,
  safetensors,
  accelerate,
  scipy,
  xformers ? null,
  cudaSupport ? false,
}:

buildPythonPackage rec {
  pname = "ltx-core";
  version = "1.0.0-unstable-2026-02-09";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "Lightricks";
    repo = "LTX-2";
    rev = "28c3c73fe557666c3de176e1e50a5220152ccfca";
    hash = "sha256-9taWJ4FIkx9tBtcx3cCFYLTGYkzbDWwVxED76clBWyo=";
  };

  sourceRoot = "source/packages/ltx-core";

  patches = [
    ./fix-transformers-5x-compat.patch
  ];

  # Patch to replace uv_build with setuptools
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail 'requires = ["uv_build>=0.9.8,<0.10.0"]' 'requires = ["setuptools"]' \
      --replace-fail 'build-backend = "uv_build"' 'build-backend = "setuptools.build_meta"'
  '';

  build-system = [ setuptools ];

  dependencies = [
    torch
    torchaudio
    einops
    numpy
    transformers
    safetensors
    accelerate
    scipy
  ] ++ lib.optionals cudaSupport [ xformers ];

  pythonImportsCheck = [ "ltx_core" ];

  # No tests in upstream
  doCheck = false;

  meta = {
    description = "Core library for LTX-2 video generation model";
    homepage = "https://github.com/Lightricks/LTX-2";
    license = lib.licenses.asl20;
  };
}
