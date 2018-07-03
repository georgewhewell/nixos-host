{ lib, buildPythonPackage, fetchFromGitHub, nodejs }:

buildPythonPackage rec {
  pname = "raven";
  version = "8.22.0";

  src = fetchFromGitHub {
    owner = "getsentry";
    repo = "sentry";
    rev = version;
    sha256 = "0plvmm4n4bwdalsa60ljayrab019sy60bxfsv8yyhp526a90flwr";
  };

  # way too many dependencies to run tests
  # see https://github.com/getsentry/raven-python/blob/master/setup.py
  doCheck = false;

  propagatedBuildInputs = [ nodejs ];

  meta = {
    description = "A Python client for Sentry (getsentry.com)";
    homepage = https://github.com/getsentry/raven-python;
    license = [ lib.licenses.bsd3 ];
    maintainers = with lib.maintainers; [ primeos ];
  };
}
