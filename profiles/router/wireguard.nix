{
  config,
  lib,
  mkSecret,
  ...
}: {
  sops.secrets.wg-home-key = mkSecret "wg-home-key" {};
  sops.secrets.wg-home-ios-psk = mkSecret "wg-home-ios-psk" {};

  # Central place to declare WireGuard peers for the router. Once keys are in
  # place, flip enable = true and add peers with their public keys.
  networking.wireguard-helpers.networks.home = {
    enable = true;
    interface = "wg-home";

    addresses = [
      "192.168.24.1/24"
      "fdde:ad:24::1/64"  # ULA for WG
    ];

    subnets = [
      "192.168.24.0/24"
      # Note: IPv6 not added here - subnets is used for NAT which is IPv4 only
    ];

    listenPort = 51820;
    privateKeyFile = config.sops.secrets.wg-home-key.path; # populated by sops-nix
    endpoint = "satanic.link:51820";
    dns = ["192.168.23.1"];

    # AllowedIPs pushed to clients; add LAN segments you want reachable.
    clientRoutes = [
      "192.168.23.0/24" # LAN
      "192.168.24.0/24" # WG network
      "fdde:ad::/48"    # ULA range
    ];

    # Set to true to have the module append subnets to nat.internalIPs instead of
    # doing it manually in router/linux.nix.
    nat.addInternalIPs = true;
    peers = {
      macbook = {
        ip = "192.168.24.10";
        publicKey = "6cTKDAKaQLfT0JbZC+R9HJi4pNEp44Qzvwm5GxKe0Ho=";
        persistentKeepalive = 25;
        fullTunnel = true;
        extraClientRoutes = ["fdde:ad::/48"];
      };
      ios = {
        ip = "192.168.24.11";
        publicKey = "jYQhJZO8/rYJzFEH39tn+kAsKyTFPkCcUv+LLetJe3c=";
        presharedKeyFile = config.sops.secrets.wg-home-ios-psk.path;
        persistentKeepalive = 25;
        fullTunnel = true;
        extraClientRoutes = ["fdde:ad::/48"];
      };
    };
  };
}
