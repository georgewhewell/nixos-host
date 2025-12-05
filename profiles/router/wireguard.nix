{
  config,
  lib,
  mkSecret,
  ...
}: {
  sops.secrets.wg-home-key = mkSecret "wg-home-key" {};

  # Central place to declare WireGuard peers for the router. Once keys are in
  # place, flip enable = true and add peers with their public keys.
  networking.wireguard-helpers.networks.home = {
    enable = true;
    interface = "wg-home";

    addresses = [
      "192.168.24.1/24"
      # Add an IPv6 prefix if you want ULA access over WG, e.g.
      # "fd6c:6c58:3edd:24::1/64"
    ];

    subnets = [
      "192.168.24.0/24"
      # "fd6c:6c58:3edd:24::/64"
    ];

    listenPort = 51820;
    privateKeyFile = config.sops.secrets.wg-home-key.path; # populated by sops-nix
    endpoint = "router.satanic.link:51820";
    dns = ["192.168.23.1"];

    # AllowedIPs pushed to clients; add LAN segments you want reachable.
    clientRoutes = [
      "192.168.23.0/24" # LAN
      "192.168.24.0/24" # WG network
    ];

    # Set to true to have the module append subnets to nat.internalIPs instead of
    # doing it manually in router/linux.nix.
    nat.addInternalIPs = true;
    peers = {
      macbook = {
        ip = "192.168.24.10";
        publicKey = "W4t76xRU2PO9Rey2iXtqRn33xNlPD8BgTFKaOfa0CAY=";
        persistentKeepalive = 25;
        fullTunnel = true;
        extraClientRoutes = ["fd6c:6c58:3edd::/48"];
      };
      ios = {
        ip = "192.168.24.11";
        publicKey = "stLHKPH8Hl7g6OZ8QXk9VEN2aBIAHyhNaH8XvXkfY0s=";
        persistentKeepalive = 25;
        fullTunnel = true;
        extraClientRoutes = ["fd6c:6c58:3edd::/48"];
      };
    };
  };
}
