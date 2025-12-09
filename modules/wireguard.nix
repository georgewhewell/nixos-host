{config, lib, ...}: let
  cfg = config.networking.wireguard-helpers;

  mkPeerAllowedIPs = peer:
    [ "${peer.ip}/32" ]
    ++ lib.optional (peer.ipv6 != null) "${peer.ipv6}/128";

  mkClientAllowedIPs = network: peer: let
    baseRoutes =
      if network.clientRoutes != []
      then network.clientRoutes
      else network.subnets;
  in
    lib.unique (
      baseRoutes
      ++ peer.extraClientRoutes
      ++ lib.optionals peer.fullTunnel ["0.0.0.0/0" "::/0"]
    );
in {
  options.networking.wireguard-helpers = {
    networks = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({name, ...}: {
        options = {
          enable = lib.mkEnableOption "WireGuard network ${name}";

          interface = lib.mkOption {
            type = lib.types.str;
            default = "wg-${name}";
            description = "Interface name for this WireGuard network.";
          };

          addresses = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "IP addresses (with prefix) to assign to the interface.";
          };

          subnets = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "CIDRs reachable through this interface (used for NAT/client defaults).";
          };

          listenPort = lib.mkOption {
            type = lib.types.port;
            default = 51820;
            description = "UDP port to listen on.";
          };

          privateKeyFile = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = "Path to the interface private key (e.g. sops secret).";
          };

          endpoint = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Public endpoint advertised to clients (host:port).";
          };

          dns = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "DNS servers to include in generated client profiles.";
          };

          clientRoutes = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "Default routes pushed to clients (falls back to subnets when empty).";
          };

          nat = {
            addInternalIPs = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Append subnets to networking.nat.internalIPs when enabled.";
            };
          };

          peers = lib.mkOption {
            type = lib.types.attrsOf (lib.types.submodule ({name, ...}: {
              options = {
                ip = lib.mkOption {
                  type = lib.types.str;
                  description = "IPv4 address (without mask) for ${name} on this network.";
                };

                ipv6 = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                  description = "IPv6 address (without mask) for ${name} on this network.";
                };

                publicKey = lib.mkOption {
                  type = lib.types.str;
                  description = "WireGuard public key for ${name}.";
                };

                presharedKeyFile = lib.mkOption {
                  type = lib.types.nullOr lib.types.path;
                  default = null;
                  description = "Optional preshared key file for this peer.";
                };

                persistentKeepalive = lib.mkOption {
                  type = lib.types.nullOr lib.types.int;
                  default = null;
                  description = "Optional persistent keepalive interval in seconds.";
                };

                extraClientRoutes = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [];
                  description = "Additional AllowedIPs to push to this peer.";
                };

                fullTunnel = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                  description = "Add 0.0.0.0/0 and ::/0 to this peer's AllowedIPs.";
                };
              };
            }));
            default = {};
            description = "Peers allowed to connect to this WireGuard network.";
          };
        };
      }));
      default = {};
      description = "Declarative WireGuard network definitions (server + peers).";
    };

    peerConfigs = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf (lib.types.attrsOf lib.types.anything));
      default = {};
      readOnly = true;
      description = "Derived server-side peer configs per network.";
    };

    clientProfiles = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf (lib.types.attrsOf lib.types.anything));
      default = {};
      readOnly = true;
      description = "Derived client profile data (addresses, AllowedIPs, endpoint, DNS).";
    };

    clientConfigData = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
      readOnly = true;
      description = "Data needed for generating client configs (used by wg-client-config.sh).";
    };
  };

  config = let
    perNetwork =
      lib.mapAttrs
      (name: network: let
        peerList =
          lib.mapAttrsToList (_peerName: peer: let
            baseAllowed = mkPeerAllowedIPs peer;
          in
            {
              inherit (peer) publicKey;
              allowedIPs = baseAllowed;
            }
            // lib.optionalAttrs (peer.presharedKeyFile != null) {presharedKeyFile = peer.presharedKeyFile;}
            // lib.optionalAttrs (peer.persistentKeepalive != null) {persistentKeepalive = peer.persistentKeepalive;}
          )
          network.peers;

        clientProfiles =
          lib.mapAttrs (
            _peerName: peer: let
              routes = mkClientAllowedIPs network peer;
              addresses =
                [ "${peer.ip}/32" ]
                ++ lib.optional (peer.ipv6 != null) "${peer.ipv6}/128";
            in {
              inherit routes addresses;
              allowedIPs = routes;
              dns = network.dns;
              endpoint = network.endpoint;
              interface = network.interface;
              listenPort = network.listenPort;
              publicKey = peer.publicKey;
            })
          network.peers;

        clientConfigData =
          lib.mapAttrs (_peerName: peer: let
            # Split routes: base routes + extra, but NOT fullTunnel routes
            baseRoutes =
              if network.clientRoutes != []
              then network.clientRoutes
              else network.subnets;
            splitRoutes = lib.unique (baseRoutes ++ peer.extraClientRoutes);
          in {
            address = "${peer.ip}/32";
            addressV6 = lib.optionalString (peer.ipv6 != null) "${peer.ipv6}/128";
            dns = network.dns;
            endpoint = network.endpoint;
            splitAllowedIPs = splitRoutes;
            fullAllowedIPs = ["0.0.0.0/0" "::/0"];
            persistentKeepalive = peer.persistentKeepalive;
          }) network.peers;
      in
        {
          inherit name peerList clientProfiles clientConfigData;
          inherit (network) interface addresses listenPort privateKeyFile subnets dns endpoint enable;
          natAddInternal = network.nat.addInternalIPs;
        })
      cfg.networks;
  in {
    assertions =
      lib.concatLists
      (lib.mapAttrsToList
        (name: network:
          lib.optionals network.enable [
            {
              assertion = network.privateKeyFile != null;
              message = "networking.wireguard-helpers.networks.${name}.privateKeyFile must be set when enable = true.";
            }
            {
              assertion = network.addresses != [];
              message = "networking.wireguard-helpers.networks.${name}.addresses must be set when enable = true.";
            }
          ])
        perNetwork);

    networking = {
      wireguard.interfaces =
        lib.mkMerge
        (lib.mapAttrsToList
          (_: network:
            lib.mkIf network.enable {
              ${network.interface} = {
                inherit (network) listenPort privateKeyFile;
                ips = network.addresses;
                peers = network.peerList;
              };
            })
          perNetwork);

      firewall.allowedUDPPorts =
        lib.mkAfter (
          lib.concatLists
          (lib.mapAttrsToList (_: network: lib.optionals network.enable [network.listenPort]) perNetwork)
        );

      nat.internalIPs =
        lib.mkAfter (
          lib.concatLists
          (lib.mapAttrsToList (_: network: lib.optionals (network.enable && network.natAddInternal) network.subnets) perNetwork)
        );

      wireguard-helpers = {
        peerConfigs =
          lib.mkMerge
          (lib.mapAttrsToList
            (_: network:
              lib.mkIf network.enable { ${network.name} = network.peerList; })
            perNetwork);

        clientProfiles =
          lib.mkMerge
          (lib.mapAttrsToList
            (_: network:
              lib.mkIf network.enable { ${network.name} = network.clientProfiles; })
            perNetwork);

        clientConfigData =
          lib.mkMerge
          (lib.mapAttrsToList
            (_: network:
              lib.mkIf network.enable { ${network.name} = network.clientConfigData; })
            perNetwork);
      };
    };
  };
}
