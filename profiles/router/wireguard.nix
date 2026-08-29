{ config
, lib
, mkSecret
, network
, ...
}:
let
  wg = network.vlans.wireguard;
  hydraBuilders = network.hydraBuilders;
  lanCidr = "${network.vlans.lan.prefix}.0/${toString network.vlans.lan.cidr}";
  wgCidr = "${wg.prefix}.0/${toString wg.cidr}";
  hydraBuilderIps = lib.mapAttrsToList (_: builder: builder.ipv4) hydraBuilders.builders;
  hydraBuilderIpSet = lib.concatStringsSep ", " hydraBuilderIps;
in
{
  assertions = [
    {
      assertion = builtins.stringLength hydraBuilders.interface <= 15;
      message = "Hydra builders WireGuard interface '${hydraBuilders.interface}' is too long; Linux interface names must be 15 characters or fewer.";
    }
  ];

  sops.secrets.wg-home-key = mkSecret "wg-home-key" { };
  sops.secrets.wg-hydra-builders-router-key = mkSecret "wg-hydra-builders-router-key" { };
  sops.secrets.wg-hydra-builders-psk = mkSecret "wg-hydra-builders-psk" { };
  sops.secrets.wg-home-ios-psk = mkSecret "wg-home-ios-psk" { };
  sops.secrets.wg-home-macbook-pro-psk = mkSecret "wg-home-macbook-pro-psk" { };

  # Central place to declare WireGuard peers for the router. Once keys are in
  # place, flip enable = true and add peers with their public keys.
  networking.wireguard-helpers.networks.home = {
    enable = true;
    interface = "wg-home";

    addresses = [
      (network.cidrOf "wireguard" wg.gatewayHost)
      "fdde:ad:24::1/64" # ULA for WG
    ];

    subnets = [
      wgCidr
      # Note: IPv6 not added here - subnets is used for NAT which is IPv4 only
    ];

    listenPort = 51820;
    privateKeyFile = config.sops.secrets.wg-home-key.path; # populated by sops-nix
    endpoint = "${network.domains.public}:51820";
    dns = [ network.dnsIp ];

    # AllowedIPs pushed to clients; add LAN segments you want reachable.
    clientRoutes = [
      lanCidr # LAN
      wgCidr # WG network
      "fdde:ad::/48" # ULA range
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
        extraClientRoutes = [ "fdde:ad::/48" ];
      };
      ios = {
        ip = network.ipOf "wireguard" 11;
        publicKey = "jYQhJZO8/rYJzFEH39tn+kAsKyTFPkCcUv+LLetJe3c=";
        presharedKeyFile = config.sops.secrets.wg-home-ios-psk.path;
        persistentKeepalive = 25;
        fullTunnel = true;
        extraClientRoutes = [ "fdde:ad::/48" ];
      };
    };
  };

  networking.wireguard.interfaces.${hydraBuilders.interface} = {
    ips = [ "${hydraBuilders.router.wg}/24" ];
    privateKeyFile = config.sops.secrets.wg-hydra-builders-router-key.path;
    peers = [
      {
        publicKey = hydraBuilders.ax102.publicKey;
        presharedKeyFile = config.sops.secrets.wg-hydra-builders-psk.path;
        allowedIPs = [ "${hydraBuilders.ax102.wg}/32" ];
        endpoint = hydraBuilders.ax102.endpoint;
        persistentKeepalive = 25;
      }
    ];
  };

  networking.nftables.tables.hydra-builders-guard = {
    family = "inet";
    content = ''
      chain forward {
        type filter hook forward priority -5; policy accept;

        iifname "${hydraBuilders.interface}" ct state established,related accept comment "allow replies to Hydra builders"
        iifname "${hydraBuilders.interface}" ip saddr ${hydraBuilders.ax102.wg} ip daddr { ${hydraBuilderIpSet} } tcp dport 22 accept comment "allow Hydra builder SSH"
        iifname "${hydraBuilders.interface}" drop comment "isolate Hydra builder tunnel"
      }
    '';
  };
}
