{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  setuptools,
  ltx-core,
  av,
  tqdm,
  pillow,
}:

buildPythonPackage rec {
  pname = "ltx-pipelines";
  version = "1.0.0-unstable-2026-02-09";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "Lightricks";
    repo = "LTX-2";
    rev = "28c3c73fe557666c3de176e1e50a5220152ccfca";
    hash = "sha256-9taWJ4FIkx9tBtcx3cCFYLTGYkzbDWwVxED76clBWyo=";
  };

  sourceRoot = "source/packages/ltx-pipelines";

  # Patch to replace uv_build with setuptools
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail 'requires = ["uv_build>=0.9.8,<0.10.0"]' 'requires = ["setuptools"]' \
      --replace-fail 'build-backend = "uv_build"' 'build-backend = "setuptools.build_meta"'
  '';

  build-system = [ setuptools ];

  dependencies = [
    ltx-core
    av
    tqdm
    pillow
  ];

  pythonImportsCheck = [ "ltx_pipelines" ];

  # No tests in upstream
  doCheck = false;

  meta = {
    description = "Pipeline implementations for LTX-2 video generation model";
    homepage = "https://github.com/Lightricks/LTX-2";
    license = lib.licenses.asl20;
  };
}
