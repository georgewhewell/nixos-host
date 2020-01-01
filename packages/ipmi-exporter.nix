{ stdenv, pkgs, lib, go, buildGoPackage, fetchFromGitHub }:

buildGoPackage rec {
  pname = "prometheus-ipmi-exporter";
  version = "2019-02-20";

  goPackagePath = "github.com/soundcloud/ipmi_exporter";

  src = fetchFromGitHub {
    owner = "soundcloud";
    repo = "ipmi_exporter";
    rev = "b478aaf12ec1728b083e007cbb9a1867f7833557";
    sha256 = "1jlhc4a5l6h9mmsx9qd2rxxp43maa0fzz6c3wrqs0fs2lnmy2g96";
  };

  doCheck = true;

  meta = with stdenv.lib; {
    description = "IPMI Exporter for Prometheus";
    homepage = https://github.com/soundcloud/ipmi_exporter;
    license = licenses.mit;
    maintainers = with maintainers; [ georgewhewell ];
    platforms = platforms.unix;
  };
}
