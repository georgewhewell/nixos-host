# A long-parked node comes back with a poisoned peer database.
#
# After this node sat stopped from 2026-07-24 to 2026-08-11, it started, logged
# "Connectivity is OFFLINE" once a second for nine hours, and never connected.
# The symptoms were misleading in both directions:
#
#   - It looked like a network fault, but was not. DNS resolved, the DNS TXT
#     seeds returned live peers, and the container could open TCP to those seeds
#     on 18189. tcpdump on the podman bridge showed no dial traffic at all,
#     because the node had already given up retrying.
#   - It looked like a tor problem, but was not. config.toml leaves
#     transport.type commented out (upstream default "tor"), but the container
#     is launched with -p base_node.p2p.transport.type=tcp, which wins.
#
# The real cause was in mainnet/log/base_node/network.log: a 572 MB peer_db
# holding 231193 peers, most long dead. Dials failed with "Connection refused"
# or "Dial timeout after 60.00s" against addresses tagged `source: Config`
# from the Feb-2026 seed list, while `#dialing_now = 93` burned a 60s timeout
# apiece. The node never reached a live peer before declaring itself offline.
#
# Fix: stop the unit, move mainnet/peer_db aside, start. It re-bootstraps from
# the DNS seeds. Within 90s: 269 successful outbound connections, peer_list
# down to 798, header sync running. peer_db is pure cache -- the node identity
# lives in mainnet/config/base_node_id.json and the chain in mainnet/data.
{
  config,
  lib,
  pkgs,
  network,
  ...
}:
with lib; let
  cfg = config.services.tari;
in {
  options.services.tari = {
    enable = mkEnableOption "Tari base node";

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/tari";
      description = "Directory to store Tari node data";
    };

    network = mkOption {
      type = types.enum ["mainnet" "stagenet" "nextnet" "localnet"];
      default = "mainnet";
      description = "Network to connect to";
    };

    port = mkOption {
      type = types.port;
      default = 18141;
      description = "Port for peer connections";
    };

    grpcPort = mkOption {
      type = types.port;
      default = 18142;
      description = "Port for gRPC connections";
    };

    walletPort = mkOption {
      type = types.port;
      default = 18143;
      description = "Port for gRPC connections";
    };

    metricsPort = mkOption {
      type = types.port;
      default = 5577;
      description = "Port for Prometheus metrics";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open firewall ports for Tari node";
    };

    image = mkOption {
      type = types.str;
      # Bumped v5.2.1 -> v5.6.0 on 2026-08-11. The node had been parked since
      # 2026-07-24 and Tari ships consensus-affecting releases often, so an
      # image five minors behind would not have synced mainnet.
      default = "quay.io/tarilabs/minotari_node:v5.6.0-mainnet";
      description = "Docker image to use for Tari node";
    };

    extraArgs = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Extra command line arguments to pass to minotari_node";
    };
  };

  config = let
    lanIp = network.primaryIp network.hosts.trex;
  in
    mkIf cfg.enable {
      virtualisation = {
        podman = {
          enable = true;
          defaultNetwork.settings.dns_enabled = true;
        };
      };

      systemd.tmpfiles.rules = [
        "d '${cfg.dataDir}' 0755 1000 1000 - -"
        "d '${cfg.dataDir}/node' 0755 1000 1000 - -"
        "d '${cfg.dataDir}/config' 0755 1000 1000 - -"
      ];

      virtualisation.oci-containers = {
        backend = "podman";
        containers.tari = {
          image = cfg.image;
          volumes = [
            "${cfg.dataDir}:/var/tari"
          ];
          environment = {
            TARI_NODE_CREATE_ID = "true";
          };
          cmd =
            [
              "--network"
              cfg.network
              "--non-interactive"
              "-p"
              "metrics.server_bind_address=0.0.0.0:${toString cfg.metricsPort}"
            ]
            ++ cfg.extraArgs;
          extraOptions = [
            "--network=bridge"
            "-p"
            "${lanIp}:${toString cfg.port}:${toString cfg.port}"
            "-p"
            "${lanIp}:${toString cfg.grpcPort}:${toString cfg.grpcPort}"
            "-p"
            "${lanIp}:${toString cfg.walletPort}:${toString cfg.walletPort}"
            "-p"
            "${lanIp}:${toString cfg.metricsPort}:${toString cfg.metricsPort}"
          ];
          autoStart = true;
        };
      };

      systemd.services.podman-tari.unitConfig.RequiresMountsFor = [cfg.dataDir];

      networking.firewall = mkIf (cfg.openFirewall && config.networking.firewall.enable) {
        allowedTCPPorts = [cfg.port cfg.grpcPort cfg.walletPort];
      };
    };
}
