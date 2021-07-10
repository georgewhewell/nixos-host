{ lib

, buildBazelPackage
, bazel

, buildPythonPackage
, fetchFromGitHub
, python

, cudatoolkit

, cython
, tensorflowWithCuda
, numpy
, scipy
, six
}:

let

  pname = "jaxlib";
  version = "0.1.65";

  meta = {
    description = "XLA library for JAX";
    homepage = "https://github.com/google/jax";
    license = lib.licenses.asl20;
  };

  bazel-build = buildBazelPackage {
    name = "bazel-build-${pname}-${version}";

    bazel = bazel;

    src = fetchFromGitHub {
        owner = "google";
        repo = "jax";
        rev = "${pname}-v${version}";
        sha256 = "19f0nljns30lmnwmdc9f0320hcgfkx09hynjwlkrpz4gbynkrnx4";
    };

    nativeBuildInputs = [
        cython
        cudatoolkit
    ];

    propagatedBuildInputs = [
        numpy
        scipy
        six
        tensorflowWithCuda
    ];

    buildBazelPackage = [ "--disable-cuda" ];

    bazelTarget = "//jaxlib";

    buildAttrs = {
      outputs = [ "out" ];
    };

    fetchAttrs = {
      sha256 = "19j57w6kc0vkfcdwr0qggy3qgrgq82kfa2jrwvvcnij4bl3wj40l";
    };

    inherit meta;
  };



  python-package = buildPythonPackage rec {
    inherit pname version;
    format = "other";

    src = bazel-build;

    inherit meta;
  };

in python-package
