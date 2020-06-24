let
  readSecret = path: (
    if builtins.pathExists ./nixos-secrets then (
      builtins.replaceStrings [ "\n" ] [ "" ]
        (builtins.readFile (./. + "/nixos-secrets/" + path))
    ) else "dummy"
  );
in
{
  grafana-admin-password = readSecret "/grafana-password.txt";
  mqtt-password = readSecret "/mqtt-password.txt";
  spotify-password = readSecret "/spotify-password.txt";

}
