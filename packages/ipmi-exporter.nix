{ stdenv, pkgs, lib, go, buildGoPackage, fetchFromGitHub }:

buildGoPackage rec {
  name = "ipmi_exporter-${version}";
  version = "2.0.2";
  rev = "${version}";

  goPackagePath = "github.com/lovoo/ipmi_exporter";

  src = fetchFromGitHub {
    inherit rev;
    owner = "lovoo";
    repo = "ipmi_exporter";
    sha256 = "165g3nvfbjvs5sr07b5masy2h8m9ypzwzbdcfjvv8ij156nkbjxg";
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
