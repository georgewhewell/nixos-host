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
      default = "quay.io/tarilabs/minotari_node:v5.2.1-mainnet";
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
