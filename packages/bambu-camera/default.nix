{
  lib,
  stdenvNoCC,
  python3,
}:
stdenvNoCC.mkDerivation {
  pname = "bambu-camera";
  version = "0.1.0";

  src = ./.;

  # Also the runtime interpreter: patchShebangs pins this store path into the
  # script, so python3 stays in the closure without a wrapper.
  nativeBuildInputs = [python3];

  installPhase = ''
    runHook preInstall

    install -Dm755 bambu_camera.py $out/bin/bambu-camera
    patchShebangs $out/bin/bambu-camera

    runHook postInstall
  '';

  meta = {
    description = "Bridge a LAN-mode Bambu Lab chamber camera to MJPEG on stdout";
    longDescription = ''
      The A1, A1 mini and P1 printers have no RTSP server - unlike the X1, which
      serves one on :322. They stream the chamber image over a bespoke framed
      protocol on TLS :6000 instead. This speaks that protocol and writes the
      JPEG frames straight to stdout, which is what go2rtc's `exec:` pipe source
      auto-detects as MJPEG, so no transcoding step is needed.
    '';
    mainProgram = "bambu-camera";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
