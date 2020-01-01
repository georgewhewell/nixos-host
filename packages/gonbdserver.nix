{ stdenv, pkgs, lib, go, buildGoPackage, fetchFromGitHub }:

buildGoPackage rec {
  name = "ipmi_exporter-${version}";
  version = "master";
  rev = "${version}";

  goPackagePath = "github.com/abligh/gonbdserver";

  src = fetchFromGitHub {
    owner = "abligh";
    repo = "gonbdserver";
    rev = "9abaa2fed84fea02e090dbdd16be7bd20162e8b6";
    sha256 = "265g3nvfbjvs5sr07b5masy2h8m9ypzwzbdcfjvv8ij156nkbjxg";
  };

  doCheck = true;

  propagatedBuildInputs = with pkgs; [
    ipmitool
  ];

  meta = with stdenv.lib; {
    description = "IPMI Exporter for Prometheus";
    homepage = https://github.com/prometheus/snmp_exporter;
    license = licenses.asl20;
    maintainers = with maintainers; [ oida ];
    platforms = platforms.unix;
  };
}
