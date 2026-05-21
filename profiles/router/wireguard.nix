{
  config,
  lib,
  mkSecret,
  network,
  ...
}: let
  wg = network.vlans.wireguard;
  lanCidr = "${network.vlans.lan.prefix}.0/${toString network.vlans.lan.cidr}";
  wgCidr = "${wg.prefix}.0/${toString wg.cidr}";
in {
  sops.secrets.wg-home-key = mkSecret "wg-home-key" {};
  sops.secrets.wg-home-ios-psk = mkSecret "wg-home-ios-psk" {};
  sops.secrets.wg-home-macbook-pro-psk = mkSecret "wg-home-macbook-pro-psk" {};

  # Central place to declare WireGuard peers for the router. Once keys are in
  # place, flip enable = true and add peers with their public keys.
  networking.wireguard-helpers.networks.home = {
    enable = true;
    interface = "wg-home";

    addresses = [
      (network.cidrOf "wireguard" wg.gatewayHost)
      "fdde:ad:24::1/64"  # ULA for WG
    ];

    subnets = [
      wgCidr
      # Note: IPv6 not added here - subnets is used for NAT which is IPv4 only
    ];

    listenPort = 51820;
    privateKeyFile = config.sops.secrets.wg-home-key.path; # populated by sops-nix
    endpoint = "${network.domains.public}:51820";
    dns = [network.routerIp];

    # AllowedIPs pushed to clients; add LAN segments you want reachable.
    clientRoutes = [
      lanCidr           # LAN
      wgCidr            # WG network
      "fdde:ad::/48"    # ULA range
    ];

    # Set to true to have the module append subnets to nat.internalIPs instead of
    # doing it manually in router/linux.nix.
    nat.addInternalIPs = true;
    peers = {
      macbook-pro = {
        ip = network.ipOf "wireguard" 10;
        publicKey = "6cTKDAKaQLfT0JbZC+R9HJi4pNEp44Qzvwm5GxKe0Ho=";
        presharedKeyFile = config.sops.secrets.wg-home-macbook-pro-psk.path;
        persistentKeepalive = 25;
        fullTunnel = true;
        extraClientRoutes = ["fdde:ad::/48"];
      };
      ios = {
        ip = network.ipOf "wireguard" 11;
        publicKey = "jYQhJZO8/rYJzFEH39tn+kAsKyTFPkCcUv+LLetJe3c=";
        presharedKeyFile = config.sops.secrets.wg-home-ios-psk.path;
        persistentKeepalive = 25;
        fullTunnel = true;
        extraClientRoutes = ["fdde:ad::/48"];
      };
    };
  };
}
