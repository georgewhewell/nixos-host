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

  spotify-client-id = readSecret "/spotify-client-id.txt";
  spotify-secret = readSecret "/spotify-secret.txt";

  wg-router-priv = readSecret "/wg-router-priv.key";
  wg-router-pub  = readSecret "/wg-router-pub.key";

  wg-hetzner-pub = readSecret "/wg-hetzner-priv.key";

  wg-yoga-pub  = readSecret "/wg-yoga-pub.key";
  wg-yoga-priv  = readSecret "/wg-yoga-priv.key";

  wg-swaps-router-priv = readSecret "/wg-swaps-router-priv.key";
  wg-swaps-router-pub  = readSecret "/wg-swaps-router-pub.key";
  wg-swaps-hetzner-priv = readSecret "/wg-swaps-hetzner-priv.key";
  wg-swaps-hetzner-pub  = readSecret "/wg-swaps-hetzner-pub.key";

}
