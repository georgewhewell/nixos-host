{ lib
, fetchFromGitHub
, python3
, gpsd
, makeWrapper
, stdenvNoCC
}:

# Prometheus exporter for gpsd (brendanbank/gpsd-prometheus-exporter).
#
# Upstream ships a single 664-line script plus a Debian-style systemd unit and
# /etc/default file; there is no setup.py, so this installs the script directly
# rather than pretending it is a Python distribution.
#
# The one subtlety is the `gps` import: that is gpsd's OWN Python binding, not
# the unrelated `gps3` package in nixpkgs. nixpkgs' gpsd installs it into
# $out/lib/pythonX.Y/site-packages/gps, which is not a python3Packages
# derivation, so it never lands on PYTHONPATH by itself — hence the explicit
# wrapper below. Without it the exporter dies at import time.
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "gpsd-prometheus-exporter";
  version = "1.1.19";

  src = fetchFromGitHub {
    owner = "brendanbank";
    repo = "gpsd-prometheus-exporter";
    tag = "v${finalAttrs.version}";
    hash = "sha256-87j9DpMk8T7HfeHMCZDqjVBBqydIHqE01e7+bd+6bhA=";
  };

  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ python3 ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 gpsd_exporter.py $out/bin/gpsd-prometheus-exporter
    # Upstream's shebang is /usr/bin/env python3; point it at the interpreter
    # we actually wrap so the two cannot drift apart.
    substituteInPlace $out/bin/gpsd-prometheus-exporter \
      --replace-fail '#!/usr/bin/env python3' '#!${python3.interpreter}'

    wrapProgram $out/bin/gpsd-prometheus-exporter \
      --prefix PYTHONPATH : "${python3.pkgs.prometheus-client}/${python3.sitePackages}" \
      --prefix PYTHONPATH : "${gpsd}/${python3.sitePackages}"

    # Kept for reference: upstream's Grafana dashboard, which
    # services/grafana-dashboards/ provisions a trimmed copy of.
    install -Dm644 gpsd_grafana_dashboard.json \
      $out/share/gpsd-prometheus-exporter/grafana-dashboard.json

    runHook postInstall
  '';

  meta = {
    description = "Prometheus exporter for the gpsd GPS daemon";
    longDescription = ''
      Exports gpsd's TPV/SKY reports as Prometheus metrics: per-satellite SNR,
      elevation and azimuth, fix mode, satellites seen versus used, and
      optionally PPS offset histograms and position offset from a fixed
      reference point.
    '';
    homepage = "https://github.com/brendanbank/gpsd-prometheus-exporter";
    license = lib.licenses.bsd3;
    mainProgram = "gpsd-prometheus-exporter";
    platforms = lib.platforms.linux;
  };
})
