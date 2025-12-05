{
  lib,
  python3Packages,
  fetchFromGitHub,
  hostapd,
  makeWrapper,
}:
python3Packages.buildPythonApplication rec {
  pname = "hostapd-exporter";
  version = "unstable-2020-07-06";
  format = "other";

  src = fetchFromGitHub {
    owner = "Fundacio-i2CAT";
    repo = "hostapd_prometheus_exporter";
    rev = "83155ced65c088f8d090314d9ff8eea7afb7b4a7";
    hash = "sha256-jl1eUkR4yYOX2ooNo8dEzrOJQvHan0fc1AxPLGan630=";
  };

  propagatedBuildInputs = with python3Packages; [
    prometheus-client
  ];

  patchPhase = ''
    # Fix hostapd_cli invocation to use proper -p <dir> -i <interface> format
    # The original script does: hostapd_cli -p /run/hostapd/hostapd_wlan0 status
    # But -p expects a directory, not a socket path
    # We need: hostapd_cli -p /run/hostapd -i wlan0 status

    substituteInPlace hostapd_exporter.py \
      --replace-fail "'hostapd_cli -p ' + ctrl_dir + e + ' status'" \
                     "'hostapd_cli -p ' + ctrl_dir + ' -i ' + e.split('_', 1)[1] + ' status'" \
      --replace-fail "'hostapd_cli -p ' + ctrl_dir + e + ' all_sta'" \
                     "'hostapd_cli -p ' + ctrl_dir + ' -i ' + e.split('_', 1)[1] + ' all_sta'"
  '';

  installPhase = ''
    mkdir -p $out/bin $out/libexec

    # Install the Python script
    install -Dm644 hostapd_exporter.py $out/libexec/hostapd-exporter.py

    # Create wrapper that uses Python interpreter
    makeWrapper ${python3Packages.python.interpreter} $out/bin/hostapd-exporter \
      --add-flags "$out/libexec/hostapd-exporter.py" \
      --prefix PATH : ${lib.makeBinPath [hostapd]} \
      --prefix PYTHONPATH : "$PYTHONPATH"
  '';

  nativeBuildInputs = [makeWrapper];

  meta = with lib; {
    description = "Prometheus exporter for hostapd metrics";
    homepage = "https://github.com/Fundacio-i2CAT/hostapd_prometheus_exporter";
    license = licenses.mit;
    maintainers = [];
    mainProgram = "hostapd-exporter";
  };
}
